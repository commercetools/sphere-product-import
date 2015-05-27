debug = require('debug')('spec:it:sphere-product-sync-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
{ProductImport} = require '../coffee'
Config = require '../../config'
Promise = require 'bluebird'
{ExtendedLogger} = require 'sphere-node-utils'
package_json = require '../../package.json'
slugify = require 'underscore.string/slugify'
sampleImportJson = require '../../samples/import.json'

cleanup = (logger, client) ->
  debug "Deleting old product entries..."
  client.products.all().fetch()
  .then (result) ->
    Promise.all _.map result.body.results, (e) ->
      client.products.byId(e.id).delete(e.version)
  .then (results) ->
    debug "#{_.size results} deleted."
    Promise.resolve()


describe 'product sync integration tests', ->

  beforeEach (done) ->
    @logger = new ExtendedLogger
      additionalFields:
        project_key: Config.config.project_key
      logConfig:
        name: "#{package_json.name}-#{package_json.version}"
        streams: [
          { level: 'info', stream: process.stdout }
        ]

    @import = new ProductImport @logger, Config

    @client = @import.client

    @logger.info 'About to setup...'
    cleanup(@logger, @client)
    .then -> done()
    .catch (err) -> done(_.prettify err)
  , 10000 # 10sec

  afterEach (done) ->
    @logger.info 'About to cleanup...'
    cleanup(@logger, @client)
    .then -> done()
    .catch (err) -> done(_.prettify err)
  , 10000 # 10sec

  describe 'JSON file', ->

    it 'should import two new products', (done) ->
      sampleImport = _.deepClone(sampleImportJson)
      @import._processBatches(sampleImport.products)
      .then =>
        expect(@import._summary.created).toBe 2
        expect(@import._summary.updated).toBe 0
        @client.productProjections.staged(true).fetch()
      .then (result) =>
        fetchedProducts = result.body.results
        expect(_.size fetchedProducts).toBe 2
        fetchedSkus = @import._extractUniqueSkus(fetchedProducts)
        sampleSkus = @import._extractUniqueSkus(sampleImport.products)
        commonSkus = _.intersection(sampleSkus,fetchedSkus)
        expect(_.size commonSkus).toBe _.size sampleSkus
        predicate = "masterVariant(sku=\"#{sampleImport.products[0].masterVariant.sku}\")"
        console.log(predicate)
        @client.productProjections.where(predicate).staged(true).fetch()
      .then (result) =>
        fetchedProduct = result.body.results
        expect(_.size fetchedProduct[0].variants).toBe _.size sampleImport.products[0].variants
        expect(fetchedProduct[0].name).toEqual sampleImport.products[0].name
        expect(fetchedProduct[0].slug).toEqual sampleImport.products[0].slug
        done()
      .catch done
    , 10000