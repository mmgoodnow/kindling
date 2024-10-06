import FormBody from "@fastify/formbody";
import Fastify from "fastify";
import process from "node:process";
import { BASE_PATH, PORT } from "./env.js";
import {
	downloadResource,
	redirectToSearch,
	searchResource,
	cssFileResource,
} from "./resources.js";

const fastify = Fastify({ logger: true });
fastify.register(FormBody);

fastify.register(
	(app, _, done) => {
		app.get("/search", searchResource);
		app.post("/download", downloadResource);
		app.get("/", redirectToSearch);
		app.get("/download", redirectToSearch);
		app.get("/index.css", cssFileResource);
		done();
	},
	{ prefix: BASE_PATH },
);

try {
	await fastify.listen({ port: Number(PORT), host: "0.0.0.0" });
} catch (err) {
	fastify.log.error(err);
	process.exit(1);
}
