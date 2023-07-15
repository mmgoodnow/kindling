import JsZip from "jszip";
import { Client } from "matrix-org-irc";
import Dcc from "irc-dcc";
import Fastify from "fastify";

const fastify = Fastify({
  logger: true,
});

const client = await new Promise((resolve, reject) => {
  const client = new Client("irc.irchighway.net", "kilimanjaro", {
    channels: ["#ebooks"],
  });
  let timeoutId;
  client.on("registered", () => {
    resolve(client);
    console.log("Registered as kilimanjaro");
    clearTimeout(timeoutId);
  });
  timeoutId = setTimeout(
    () => reject(new Error("registration timed out")),
    10000,
  ).unref();
});

const dcc = new Dcc(client);

function truncateNick(nick, length) {
  return Array.from({ length }, (v, i) => nick[i])
    .fill(" ", nick.length, length)
    .join("");
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
      client.removeListener(onSend);
    }

    function onSend(from, args) {
      handleSend(from, args).then(resolve, reject);
    }

    client.on("dcc-send", onSend);
  });
}

fastify.get("/search", async (request, reply) => {
  reply.header("Content-Type", "text/html");
  reply.send(`
<h1>Search</h1>
<form action="/results" method="GET">
    <input type="search" name="q">
    <input type="submit" />
</form>
`);
  return reply;
});

fastify.get("/results", async (request, reply) => {
  reply.header("Content-Type", "text/html");
  if (!request.query.q) {
    reply;
  }
});

try {
  await fastify.listen({ port: 3000 });
} catch (err) {
  fastify.log.error(err);
  process.exit(1);
}
