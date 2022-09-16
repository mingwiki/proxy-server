import http from 'http'
import https from 'https'
import httpProxy from 'http-proxy'
import fs from 'fs'
import tls from 'tls'
import { domains, preHeaders } from './config.js'
const proxy = httpProxy.createProxyServer()
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
  const host = req.headers.host.split(':')[0]
  const ip = req.headers['x-forwarded-for'] || req.connection.remoteAddress
  const domainURL = domains[host] || undefined
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
      fs.createReadStream('./wiki.png').pipe(res)
    } else {
      res.writeHead(200, preHeaders)
      res.end('Welcome to mingwiki server!')
    }
  }
}
const getSecureContext = (domain) => {
  try {
    return tls.createSecureContext({
      key: fs.readFileSync(`./certs/${domain}.key`, 'utf8'),
      cert: fs.readFileSync(`./certs/${domain}.pem`, 'utf8'),
      ca: fs.readFileSync('./certs/root.cer', 'utf8'),
    })
  } catch (error) {}
}
const preGetSecureContext = () => {
  const res = {}
  Object.keys(domains).forEach((domain) => {
    res[domain] = getSecureContext(domain)
  })
  return res
}
const secureContext = preGetSecureContext()
const options = {
  SNICallback: function (domain, cb) {
    if (secureContext[domain]) {
      if (cb) {
        cb(null, secureContext[domain])
      } else {
        return secureContext[domain]
      }
    } else {
      console.log('No keys/certificates for domain requested')
    }
  },
  cert: fs.readFileSync(`./certs/localhost.crt`, 'utf8'),
  key: fs.readFileSync(`./certs/localhost.key`, 'utf8'),
}
const httpServer = http.createServer((req, res) => {
  publicProcess(req, res)
})
const httpsServer = https.createServer(options, (req, res) => {
  publicProcess(req, res)
})
httpServer.listen(100)
httpsServer.listen(200)
