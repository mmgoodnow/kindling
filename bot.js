import Dcc from "irc-dcc";
import { Client } from "matrix-org-irc";
import net from "net";
import { createReadStream, statSync } from "node:fs";
import { basename } from "path";
import { IRC_NICK } from "./env.js";
let port = 55556;
export const client = await new Promise((resolve, reject) => {
	const client = new Client("localhost", "testbot", {
		port: 6667,
		debug: true,
		channels: ["#ebooks"],
		userName: "username",
	});
	let timeoutId;

	client.conn.on("data", (data) => {
		console.log({ inbound: data.toString() });
	});
	client.once("registered", () => {
		resolve(client);
		console.log("Registered");
		clearTimeout(timeoutId);
	});
	timeoutId = setTimeout(
		() => reject(new Error("registration timed out")),
		4000,
	).unref();
});

const dcc = new Dcc(client, { localAddress: "127.0.0.1" });

function sendFile(to, filename, length, callback) {
	filename = filename.replace(/ /g, "_");
	let start = 0;

	function onResume(from, args) {
		// https://www.mirc.com/help/html/index.html?dcc_resume_protocol.html
		if (args.filename !== filename) return;
		start = args.position;
		client.ctcp(
			from,
			"privmsg",
			`DCC ACCEPT ${filename} ${args.port} ${args.position}`,
		);
	}

	// step 1. serve the file
	const server = net.createServer();

	// step 2. when server is ready to serve, tell the user where to find the file
	server.on("listening", function () {
		client.ctcp(
			to,
			"privmsg",
			`DCC SEND ${filename} 2130706433 ${server.address().port} ${length}`,
		);
		client.once("dcc-resume", onResume);
	});

	// send the file and clean up
	server.on("connection", function (con) {
		server.close();
		callback(null, con, start);
		client.removeListener("dcc-resume", onResume);
	});

	// go
	server.listen(port++, "0.0.0.0");
}

function sendFileHighLevel(nick, filepath) {
	const stats = statSync(filepath);
	sendFile(nick, basename(filepath), stats.size, (err, con, position) => {
		if (err) {
			client.notice(nick, err);
			return;
		}
		const rs = createReadStream(filepath, { start: position });
		rs.pipe(con);
	});
}

client.on("message", async (nick, channel, message) => {
	client.say(channel, `echo ${message}`);
	await new Promise((r) => setTimeout(r, 5000));
	if (message.startsWith("@Search")) {
		sendFileHighLevel(
			nick,
			"***REMOVED***",
		);
	} else if (message.startsWith("!")) {
		sendFileHighLevel(
			nick,
			"***REMOVED***",
		);
	}
});
