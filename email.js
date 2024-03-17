import NodeMailer from "nodemailer";
import {
	KINDLE_EMAIL_ADDRESS,
	SENDER_EMAIL_ADDRESS,
	SENDER_EMAIL_AS,
	SENDER_EMAIL_PASSWORD,
	SENDER_NAME,
	SMTP_HOST,
	SMTP_PORT,
} from "./env.js";

const transporter = NodeMailer.createTransport({
	host: SMTP_HOST,
	port: Number(SMTP_PORT),
	secure: false,
	auth: { user: SENDER_EMAIL_ADDRESS, pass: SENDER_EMAIL_PASSWORD },
});

export async function sendEmail(filename, buf) {
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
