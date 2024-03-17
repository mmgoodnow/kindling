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
	NODE_ENV,
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

function html(body) {
	return `
		<!DOCTYPE html>
		<html lang="en">
  			<head>
    			<meta charset="UTF-8" />
    			<meta name="viewport" content="width=device-width, initial-scale=1.0" />
    			<title>Kindling</title>
    			<base href="${BASE_PATH}/" />
    			<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" />
    			<link rel="stylesheet" href="index.css" />
    			<iframe hidden name=htmz onload="setTimeout(()=>document.querySelector(contentWindow.location.hash||null)?.replaceWith(...contentDocument.body.childNodes))"></iframe>
  			</head>
  			<body class="container">
  				${body}
  			</body>
		</html>
	`;
}

function cssFile(request, reply) {
	const cssText = `
*, *::before, *::after { box-sizing: border-box; }
body { 
	line-height: 1.5;
	-webkit-font-smoothing: antialiased;
	font-family: -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif 
}
img, picture, video, canvas, svg {
	display: block;
	max-width: 100%;
}
p, h1, h2, h3, h4, h5, h6 { overflow-wrap: break-word; }
#root, #__next { isolation: isolate; }
.custom-row {
	display: flex;
	flex-direction: row;
	gap: 0.5rem;
}
.custom-col {
	display: flex;
	flex-direction: column;
}
.custom-items {
	display: flex;
	flex-direction: column;
	gap: 0.5rem;
}
`;
	reply.header("Content-Type", "text/css");
	return cssText;
}

function parseSearchResultStr(result) {
	const {
		name,
		server = "Unknown Server",
		size = "Unknown Size",
	} = /^!(?<server>\w+) (?<name>.+?)( ::INFO:: (?<size>.+))?$/.exec(
		result.trim(),
	)?.groups ?? { name: result.trim() };
	return { name: name.trim(), server, size };
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

	check(token) {
		return this.activeTokens.has(token);
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

function listItem({ name, server, size }, token, i) {
	return `
		<form action="download#result-${i}" method="POST" target="htmz">
			<div class="custom-row">
				<div class="col flex-shrink-1 flex-grow-0">
					<input id="result-${i}" class="btn btn-sm btn-outline-primary" type="submit" name="f" value="Download" />
				</div>
				<div class="custom-col flex-grow-1">
					<span><strong>${name}</strong></span>
					<span>${server} (${size})</span>
				</div>
			</div>
			<input type="hidden" name="token" value="${token}">
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

function cleanse(message) {
	return message.replaceAll(/[^\w ]/g, " ").replaceAll(/\s+/g, " ");
}

function receiveNoMatchesNotice(q) {
	return new Promise((resolve) => {
		function onNotice(from, to, message) {
			if (
				from === "Search" &&
				message.includes(q) &&
				cleanse(message).includes("returned no matches")
			) {
				resolve([]);
			}
		}
		client.on("notice", onNotice);
		setTimeout(() => {
			client.off("notice", onNotice);
		}, ms("10 seconds"));
	});
}

async function getSearchResults() {
	const [, buffer] = await receiveDcc();
	const zip = await JsZip.loadAsync(buffer);
	const { name } = Object.values(zip.files)[0];
	const textContent = await zip.file(name).async("string");
	return textContent
		.split("\n")
		.filter((line) => line.startsWith("!"))
		.map((line) => line.trim());
}

async function search(q) {
	client.say("#ebooks", `@search ${q}`);
	return Promise.race([getSearchResults(), receiveNoMatchesNotice(q)]);
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
			<form class="input-group" action="search" method="GET">
				<input class="form-control" type="search" name="q" />
				<input class="btn btn-primary" type="submit" />
			</form>
		`);
	}

	const results = await search(request.query.q);
	const token = tokenManager.create();

	const resultsStr = `
		<div class="custom-items">
			${results
				.map(parseSearchResultStr)
				.filter((r) => r.name.includes(".epub") && !r.name.endsWith("rar"))
				.sort((a, b) => {
					const priority = ["peapod", "Oatmeal"];
					const x = priority.indexOf(a.server);
					const y = priority.indexOf(b.server);
					return y - x;
				})
				.map((r, i) => listItem(r, token, i))
				.join("")}
		</div>`;
	return html(`
		<h1>Search</h1>
		<form class="input-group" action="search" method="GET">
			<input class="form-control" type="search" name="q" value="${request.query.q}" />
			<input class="btn btn-primary" type="submit" />
		</form>
		<br />
		<h1>Results</h1>
			${results.length > 0 ? resultsStr : `No results for "${request.query.q}"`}
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

	if (!tokenManager.check(request.body.token)) {
		throw {
			statusCode: 400,
			message: "Form token invalid. Go back to the search page and refresh.",
		};
	}

	let filename, buf;
	reply.header("Content-Type", "text/html");
	try {
		[filename, buf] = await download(request.body.f);
	} catch (e) {
		console.error(e);
		return `<span class="btn btn-sm btn-danger">Failure</span>`;
	}

	if (NODE_ENV !== "development") {
		await sendEmail(filename, buf);
	}
	return `<span class="btn btn-sm btn-success">Success</span>`;
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
		app.get("/index.css", cssFile);
		done();
	},
	{ prefix: BASE_PATH },
);

try {
	await fastify.listen({ port: PORT, host: "0.0.0.0" });
} catch (err) {
	fastify.log.error(err);
	process.exit(1);
}
