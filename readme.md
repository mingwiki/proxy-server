# Proxy Server

## Installation

```shell
$ npm i -g forever && npm i && mv config.yml.example config.yml
```

## Usage

```shell
$ forever start -a -l forever.log -o out.log -e err.log app
```

## Configuration

> Edit the config.yml file in your application
