FROM node:20-bookworm
WORKDIR /usr/src/app
RUN apt-get update
RUN apt-get install -y libopengl0 libegl1
RUN curl -fsSL https://download.calibre-ebook.com/linux-installer.sh | sh
COPY package.json pnpm-lock.yaml ./
RUN corepack enable
RUN pnpm install --frozen-lockfile --prod
COPY index.js ./
ENV PORT=6015
EXPOSE 6015
ENTRYPOINT ["node", "index.js"]
