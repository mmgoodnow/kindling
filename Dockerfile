FROM node:20-slim
RUN curl -f https://get.pnpm.io/v6.16.js | node - add --global pnpm
WORKDIR /usr/src/app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod
ENV PORT=6015
EXPOSE 6015
ENTRYPOINT ["node", "index.js"]
