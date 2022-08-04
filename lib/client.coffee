fetch = require 'isomorphic-fetch'
{ ClientBuilder } = require '@commercetools/sdk-client-v2'
{ createApiBuilderFromCtpClient } = require '@commercetools/platform-sdk'
packageJson = require './../package.json'

createCtpClient = ({ client_id, client_secret, project_key }) ->
  return new ClientBuilder()
    .withClientCredentialsFlow({
      host: 'https://auth.europe-west1.gcp.commercetools.com',
      projectKey: project_key,
      credentials: {
        clientId: client_id,
        clientSecret: client_secret,
      },
      fetch,
    })
    .withHttpMiddleware({
      maskSensitiveHeaderData: true,
      host: 'https://api.europe-west1.gcp.commercetools.com',
      enableRetry: true,
      retryConfig: {
        retryCodes: [500, 502, 503, 504],
      },
      fetch,
    })
    .withQueueMiddleware({concurrency: 10})
    .withUserAgentMiddleware({
      libraryName: packageJson.name,
      libraryVersion: packageJson.version,
      contactUrl: packageJson.homepage,
      contactEmail: packageJson.author.email,
    })
    .build()

getApiRoot = (config) ->
  ctpClient = createCtpClient(config)
  apiRoot = createApiBuilderFromCtpClient(ctpClient).withProjectKey({
    projectKey: config.project_key,
  })
  return apiRoot


module.exports =
  getApiRoot: getApiRoot
