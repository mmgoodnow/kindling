import FormBody from "@fastify/formbody";
import { randomUUID } from "crypto";
import Fastify from "fastify";
import { writeFileSync } from "fs";
import { readFile, writeFile } from "fs/promises";
import Dcc from "irc-dcc";
import JsZip from "jszip";
import { Client } from "matrix-org-irc";
import ms from "ms";
import { tmpdir } from "os";
import { join, extname, basename } from "path";
import { exec, execFile } from "child_process";
import { promisify } from "util";

const fastify = Fastify({ logger: true });
fastify.register(FormBody);

const client = await new Promise((resolve, reject) => {
	const client = new Client("irc.irchighway.net", "kilimanjaro", {
		channels: ["#ebooks"],
		onNickConflict: () => "kilimanjaro" + Math.random().toString()[2],
	});
	let timeoutId;
	client.on("registered", () => {
		resolve(client);
		console.log("Registered");
		clearTimeout(timeoutId);
	});
	timeoutId = setTimeout(
		() => reject(new Error("registration timed out")),
		4000,
	).unref();
});

const dcc = new Dcc(client);

class TokenManager {
	constructor() {
		this.activeTokens = new Set();
	}

	create() {
		const token = randomUUID();
		this.renew(token);
		return token;
	}

	renew(token) {
		this.activeTokens.add(token);
		setTimeout(() => void this.checkAndRevoke(token), ms("10 minutes"));
	}

	checkAndRevoke(token) {
		return this.activeTokens.delete(token);
	}
}

const tokenManager = new TokenManager();

function listItem(r) {
	return `
		<li>
			<form action="/download" method="POST">
				<input type="submit" name="f" value="${r}" />
			</form>
		</li>
	`;
}

async function maybeConvert(filename, buf) {
	if (extname(filename) === "mobi") {
		return [filename, buf];
	}
	const oldFn = join(tmpdir(), filename);
	const withoutExtension = basename(filename, extname(filename));
	const newFn = join(tmpdir(), `${withoutExtension}.mobi`);
	await writeFile(oldFn, buf);
	try {
		const output = await promisify(execFile)("ebook-convert", [oldFn, newFn]);
		console.log(output.stdout);
		console.error(output.stderr);
	} catch (e) {
		console.log(e.stdout);
		console.error(e.stderr);
		throw e;
	}

	return [basename(newFn), await readFile(newFn)];
}

function search(q) {
	client.say("#ebooks", `@search ${q}`);
	return new Promise((resolve, reject) => {
		async function handleSend(from, args) {
			const buffer = await new Promise((resolve, reject) => {
				dcc.acceptFile(
					from,
					args.host,
					args.port,
					args.filename,
					args.length,
					(err, filename, connection) => {
						if (err) {
							console.log(err);
							client.notice(from, err);
							reject(err);
						}
						const bufs = [];
						connection.on("data", (d) => void bufs.push(d));
						connection.on("end", () => {
							resolve(Buffer.concat(bufs));
						});
					},
				);
			});

			const zip = await JsZip.loadAsync(buffer);
			const filename = Object.values(zip.files)[0].name;
			const textContent = await zip.file(filename).async("string");
			const lines = textContent
				.split("\n")
				.filter((line) => line.startsWith("!"))
				.map((line) => line.trim());
			resolve(lines);
		}

		function onSend(from, args) {
			handleSend(from, args).then(resolve, reject);
		}

		client.once("dcc-send", onSend);
	});
}

function download(f) {
	client.say("#ebooks", f);
	return new Promise((resolve, reject) => {
		async function handleSend(from, { host, port, filename, length }) {
			console.log(`received dcc from ${from}`);
			const buffer = await new Promise((resolve, reject) => {
				function onConnection(err, filename, connection) {
					if (err) {
						console.log(err);
						client.notice(from, err);
						reject(err);
					}
					const bufs = [];
					let bytes = 0;
					connection.on("data", (d) => {
						bufs.push(d);
						bytes += Buffer.byteLength(d);
						if (bufs.length % 10 === 0 || bufs.length === 1) {
							console.log(`${((bytes * 100) / args.length).toFixed()}%`);
						}
						if (bytes === args.length) {
							console.log("100%");
							resolve(Buffer.concat(bufs));
						}
					});
					connection.on("error", (error) => {
						console.error(error);
						reject(error);
					});
				}

				dcc.acceptFile(from, host, port, filename, length, onConnection);
			});

			resolve([filename, buffer]);
		}

		function onSend(from, args) {
			handleSend(from, args).then(resolve, reject);
		}

		client.once("dcc-send", onSend);
	});
}

fastify.get("/search", async (request, reply) => {
	reply.header("Content-Type", "text/html");

	if (!request.query.q) {
		return `
			<h1>Search</h1>
			<form action="/search" method="GET">
					<input type="search" name="q">
					<input type="submit" />
			</form>
		`;
	}

	const results = await search(request.query.q);
	const token = tokenManager.create();

	reply.header("Content-Type", "text/html");
	return `
		<h1>Search</h1>
		<form action="/search" method="GET">
			<input type="search" name="q" value="${request.query.q}">
			<input type="hidden" name="token" value="${token}">
			<input type="submit" />
		</form>
		<h1>Results</h1>
		<ul>
			${results.map(listItem).join("")}
		</ul>
	`;
});

fastify.post("/download", async (request, reply) => {
	if (!request.body.f || !request.body.token) {
		throw {
			statusCode: 400,
			message:
				"Form submission incomplete. Go back to the search page and refresh.",
		};
	}

	if (!tokenManager.checkAndRevoke(request.body.token)) {
		throw {
			statusCode: 400,
			message: "Form token invalid. Go back to the search page and refresh.",
		};
	}

	let filename, buf;
	try {
		[filename, buf] = await download(request.body.f);
	} catch (e) {
		tokenManager.renew(request.body.token);
		throw {
			statusCode: 500,
			message: "Failed to download book, try a different server.",
		};
	}

	const [mobiFn, mobiBuf] = await maybeConvert(filename, buf);

	return "Success";
});

try {
	await fastify.listen({ port: 3000 });
} catch (err) {
	fastify.log.error(err);
	process.exit(1);
}
