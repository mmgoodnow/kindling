# kindling
Download books to kindle from IRC.

## Requirements
- node 20 definitely works, 16 probably works

```
corepack enable # corepack installs a shim for pnpm that will download it automatically when you use it
pnpm install
```

## Run
Set the following environment variables
- `SENDER_EMAIL_ADDRESS`
- `SENDER_EMAIL_PASSWORD`
- `SENDER_NAME`
- `SENDER_EMAIL_AS`
- `SMTP_HOST`
- `SMTP_PORT`
- `IRC_NICK`
- `KINDLE_EMAIL_ADDRESS`
- `PORT`
- `BASE_PATH`
- `NODE_ENV`

```
node index.js
```
