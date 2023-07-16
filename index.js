import FormBody from "@fastify/formbody";
import Fastify from "fastify";
import Dcc from "irc-dcc";
import JsZip from "jszip";
import { Client } from "matrix-org-irc";
import ms from "ms";
import { randomUUID } from "node:crypto";
import process from "node:process";
import NodeMailer from "nodemailer";

process.on("SIGINT", () => void process.exit(0));
process.on("SIGTERM", () => void process.exit(0));

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
	BASE_PATH,
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
	BASE_PATH,
};

function html(body) {
	return `
		<!DOCTYPE html>
		<html lang="en">
  			<head>
    			<meta charset="UTF-8">
    			<meta name="viewport" content="width=device-width, initial-scale=1.0">
    			<title>Kindling</title>
    			<base href="${BASE_PATH}/">
  			</head>
  			<body>
  				${body}
  			</body>
		</html>
	`;
}

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
		<form action="download" method="POST">
			<input type="hidden" name="token" value="${token}">
			<input type="submit" name="f" value="${result}" />
		</form>
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

		setTimeout(() => {
			client.off("dcc-send", onSend);
			reject(
				new Error(
					"Never received the file. Try downloading from a different server.",
				),
			);
		}, ms("10 seconds"));
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

const searchResource = async (request, reply) => {
	reply.header("Content-Type", "text/html");

	if (!request.query.q) {
		return html(`
			<h1>Search</h1>
			<form action="search" method="GET">
				<input type="search" name="q" />
				<input type="submit" />
			</form>
		`);
	}

	const results = await search(request.query.q);
	const token = tokenManager.create();

	return html(`
		<h1>Search</h1>
		<form action="search" method="GET">
			<input type="search" name="q" value="${request.query.q}" />
			<input type="submit" />
		</form>
		<h1>Results</h1>
			${results.map((r) => listItem(r, token)).join("")}
	`);
};

const downloadResource = async (request, reply) => {
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

	await sendEmail(filename, buf);
	reply.header("Content-Type", "text/html");
	return html(`
		<h1>Download Successful</h1>
		<a href="search">Return to search</a>
	`);
};
const redirectToSearch = function (request, reply) {
	reply.redirect(`${BASE_PATH}/search`);
	return reply;
};

fastify.register(
	(app, _, done) => {
		app.get("/search", searchResource);
		app.post("/download", downloadResource);
		app.get("/", redirectToSearch);
		app.get("/download", redirectToSearch);
		done();
	},
	{ prefix: BASE_PATH },
);

try {
	await fastify.listen({ port: PORT });
} catch (err) {
	fastify.log.error(err);
	process.exit(1);
}
