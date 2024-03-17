import { sendEmail } from "./email.js";
import { BASE_PATH, NODE_ENV } from "./env.js";
import { download, search } from "./irc.js";
import { TokenManager } from "./tokenManager.js";
import { html, listItem, parseSearchResultStr } from "./utils.js";

const tokenManager = new TokenManager();

export async function searchResource(request, reply) {
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
}

export async function downloadResource(request, reply) {
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
}

export function redirectToSearch(request, reply) {
	reply.redirect(`${BASE_PATH}/search`);
	return reply;
}

export function cssFileResource(request, reply) {
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
