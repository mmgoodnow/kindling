import process from "node:process";

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
