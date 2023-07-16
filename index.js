import FormBody from "@fastify/formbody";
import Fastify from "fastify";
import Dcc from "irc-dcc";
import JsZip from "jszip";
import { Client } from "matrix-org-irc";
import ms from "ms";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, extname, join } from "node:path";
import process from "node:process";
import NodeMailer from "nodemailer";

process.on("SIGINT", () => void process.exit(0));
process.on("SIGTERM", () => void console.log("Terminating"));

export const {
	SENDER_EMAIL_ADDRESS,
	SENDER_EMAIL_PASSWORD,
	SENDER_NAME,
	SENDER_EMAIL_AS,
	SMTP_HOST,
	SMTP_PORT,
	IRC_NICK,
	KINDLE_EMAIL_ADDRESS,
	PORT,
} = process.env;

const requireds = {
	SENDER_EMAIL_ADDRESS,
	SENDER_EMAIL_PASSWORD,
	SENDER_NAME,
	SENDER_EMAIL_AS,
	SMTP_HOST,
	SMTP_PORT,
	IRC_NICK,
	KINDLE_EMAIL_ADDRESS,
	PORT,
};

let bad = false;
for (const [key, value] of Object.entries(requireds)) {
	if (!value) {
		bad = true;
		console.error(`config not specified: ${key}`);
	}
}

if (bad) {
	throw new Error("Some config options not specified");
}

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

const fastify = Fastify({ logger: true });
fastify.register(FormBody);

const client = await new Promise((resolve, reject) => {
	const client = new Client("irc.irchighway.net", IRC_NICK, {
		channels: ["#ebooks"],
		onNickConflict: () => IRC_NICK + Math.random().toString()[2],
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

const tokenManager = new TokenManager();

const transporter = NodeMailer.createTransport({
	host: SMTP_HOST,
	port: Number(SMTP_PORT),
	secure: false,
	auth: { user: SENDER_EMAIL_ADDRESS, pass: SENDER_EMAIL_PASSWORD },
});

function listItem(result, token) {
	return `
		<li>
			<form action="/download" method="POST">
				<input type="hidden" name="token" value="${token}">
				<input type="submit" name="f" value="${result}" />
			</form>
		</li>
	`;
}

function receiveDcc() {
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
							console.log(`${((bytes * 100) / length).toFixed()}%`);
						}
						if (bytes === length) {
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

async function search(q) {
	client.say("#ebooks", `@search ${q}`);
	const [, buffer] = await receiveDcc();
	const zip = await JsZip.loadAsync(buffer);
	const { name } = Object.values(zip.files)[0];
	const textContent = await zip.file(name).async("string");
	return textContent
		.split("\n")
		.filter((line) => line.startsWith("!"))
		.map((line) => line.trim());
}

function download(f) {
	client.say("#ebooks", f);
	return receiveDcc();
}

async function maybeConvert(filename, buf) {
	if (extname(filename) === "mobi") {
		return [filename, buf];
	}
	const oldFn = join(tmpdir(), filename);
	const withoutExtension = basename(filename, extname(filename));
	const newFn = join(tmpdir(), `${withoutExtension}.mobi`);
	await writeFile(oldFn, buf);

	await new Promise((resolve, reject) => {
		const ebookConvert = spawn("ebook-convert", [oldFn, newFn], {
			stdio: "inherit",
		});
		ebookConvert.on("close", () => {
			console.log("Conversion finished");
			resolve();
		});
		ebookConvert.on("error", reject);
	});

	const mobiBuf = await readFile(newFn);
	await unlink(newFn);
	return [basename(newFn), mobiBuf];
}

async function sendEmail(filename, buf) {
	console.log("Sending email…");
	const info = await transporter.sendMail({
		from: `${SENDER_NAME} <${SENDER_EMAIL_AS}>`,
		to: KINDLE_EMAIL_ADDRESS,
		subject: `eBook attached: ${filename}`,
		text: `${filename}\n`,
		attachments: { filename, content: buf },
	});
	console.log("Email sent", info);
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

	return `
		<h1>Search</h1>
		<form action="/search" method="GET">
			<input type="search" name="q" value="${request.query.q}">
			<input type="submit" />
		</form>
		<h1>Results</h1>
		<ul>
			${results.map((r) => listItem(r, token)).join("")}
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
	await sendEmail(mobiFn, mobiBuf);
	reply.header("Content-Type", "text/html");
	return `
		<h1>Download Successful</h1>
		<a href="/search">Return to search</a>
	`;
});

fastify.get("/", (request, reply) => {
	reply.redirect("/search");
	return reply;
});

fastify.get("/download", (request, reply) => {
	reply.redirect("/search");
});

try {
	await fastify.listen({ port: PORT });
} catch (err) {
	fastify.log.error(err);
	process.exit(1);
}
