FROM node:16

# Create app directory
WORKDIR /usr/src/app

# Install app dependencies
# A wildcard is used to ensure both package.json AND package-lock.json are copied
# where available (npm@5+)
COPY package*.json ./
COPY yarn*.lock ./

RUN yarn install --immutable

# Bundle app source
COPY . .

EXPOSE 3000
ENV NODE_ENV=production
CMD [ "yarn", "start" ]
