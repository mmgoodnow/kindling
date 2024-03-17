FROM node:20
WORKDIR /usr/src/app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable
RUN pnpm install --frozen-lockfile --prod
COPY *.js ./
ENV PORT=6015
EXPOSE 6015
ENTRYPOINT ["node", "index.js"]
