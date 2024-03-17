import Dcc from "irc-dcc";
import JsZip from "jszip";
import { Client } from "matrix-org-irc";
import ms from "ms";
import { IRC_NICK } from "./env.js";
import { cleanse } from "./utils.js";

export const client = await new Promise((resolve, reject) => {
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

export function receiveDcc() {
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

export function receiveNoMatchesNotice(q) {
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

export async function search(q) {
	client.say("#ebooks", `@search ${q}`);
	return Promise.race([getSearchResults(), receiveNoMatchesNotice(q)]);
}

export function download(f) {
	client.say("#ebooks", f);
	return receiveDcc();
}
