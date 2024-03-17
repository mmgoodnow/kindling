import ms from "ms";
import { randomUUID } from "node:crypto";

export class TokenManager {
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
