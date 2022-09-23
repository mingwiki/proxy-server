#!/usr/bin/env node
const http = require('http')
const https = require('https')
const { createReadStream, readFileSync } = require('fs')
const tls = require('tls')
const httpProxy = require('http-proxy')
const parse = require('yaml').parse
const proxy = httpProxy.createProxyServer()
const config = parse(
  readFileSync('./config.yml', 'utf8') || readFileSync('./config.yaml', 'utf8'),
)
const subdomains = config['subdomains']
const http_port = config['ports']?.http || 80
const https_port = config['ports']?.https || 443
const CertCA = config['ca']
const getSubdomain = (domain) =>
  domain.split(':')[0].split('.').slice(0, -2).join('.') || 'www'
proxy.on('error', function (err, req, res) {
  console.log(err)
  res.writeHead(500, {
    'Content-Type': 'text/plain',
  })
  res.end('Something went wrong. And we are reporting a custom error message.')
})
proxy.on('open', function (proxySocket) {
  console.log('open', proxySocket)
})
proxy.on('proxyReq', function (proxyReq, req, res, options) {
  for (const [k, v] of Object.entries(preHeaders)) {
    res.setHeader(k, v)
  }
})
proxy.on('upgrade', function (req, socket, head) {
  proxy.ws(req, socket, head)
})
proxy.on('close', function (res, socket, head) {
  console.log('Client disconnected')
})
const publicProcess = (req, res) => {
  const subdomain = getSubdomain(req.headers.host)
  const ip = req.headers['x-forwarded-for'] || req.connection.remoteAddress
  const domainURL = subdomains[subdomain]?.proxy || undefined
  if (domainURL) {
    proxy.web(req, res, {
      target: domainURL,
      secure: false,
      changeOrigin: true,
    })
  } else {
    const path = req.url.startsWith('http')
      ? new URL(req.url).pathname
      : req.url
    if (path.startsWith('/favicon.ico')) {
      res.setHeader('Content-Type', 'image/png')
      createReadStream('etc/favicon.png').pipe(res)
    } else {
      res.writeHead(200, preHeaders)
      res.end('Welcome to mingwiki server!')
    }
  }
}
const getSecureContext = (subdomain) => {
  try {
    return tls.createSecureContext({
      key: readFileSync(subdomains[subdomain]?.key || '', 'utf8'),
      cert: readFileSync(subdomains[subdomain]?.cert || '', 'utf8'),
      ca: readFileSync(CertCA, 'utf8'),
    })
  } catch (error) {}
}
const preGetSecureContext = () => {
  const res = {}
  Object.keys(subdomains).forEach((subdomain) => {
    res[subdomain] = getSecureContext(subdomain)
  })
  return res
}
const secureContext = preGetSecureContext()
const options = {
  SNICallback: function (domain, cb) {
    const domainConfig = secureContext[getSubdomain(domain)]
    if (domainConfig) {
      if (cb) {
        cb(null, domainConfig)
      } else {
        return domainConfig
      }
    } else {
      console.log('No keys/certificates for domain requested')
    }
  },
  cert: readFileSync(`certs/localhost.pem`, 'utf8'),
  key: readFileSync(`certs/localhost.key`, 'utf8'),
}
const httpServer = http.createServer((req, res) => {
  if (
    subdomains[getSubdomain(req.headers.host)]?.key &&
    subdomains[getSubdomain(req.headers.host)]?.cert
  ) {
    res.setHeader(
      'location',
      `https://${req.headers.host.split(':')[0]}:${https_port}`,
    )
    res.writeHead(301).end()
  } else {
    publicProcess(req, res)
  }
})
const httpsServer = https.createServer(options, (req, res) => {
  publicProcess(req, res)
})
console.log('Server started')
httpServer.listen(http_port)
httpsServer.listen(https_port)

const preHeaders = {
  'x-powered-by': 'mingwiki',
  'x-redirect-by': 'mingwiki',
  'x-server': 'mingwiki',
  server: 'mingwiki',
}
