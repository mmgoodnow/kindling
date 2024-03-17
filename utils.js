import { BASE_PATH } from "./env.js";

export function cleanse(message) {
	return message.replaceAll(/[^\w ]/g, " ").replaceAll(/\s+/g, " ");
}

export function html(body) {
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
    			<iframe hidden name="htmz" onload="setTimeout(()=>document.querySelector(contentWindow.location.hash||null)?.replaceWith(...contentDocument.body.childNodes))"></iframe>
  			</head>
  			<body class="container">
  				${body}
  			</body>
		</html>
	`;
}

export function parseSearchResultStr(result) {
	const {
		name,
		server = "Unknown Server",
		size = "Unknown Size",
	} = /^!(?<server>\w+) (?<name>.+?)( ::INFO:: (?<size>.+))?$/.exec(
		result.trim(),
	)?.groups ?? { name: result.trim() };
	return { name: name.trim(), server, size };
}

export function listItem({ name, server, size }, token, i) {
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
