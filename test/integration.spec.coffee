debug = require('debug')('spec:it:sphere-product-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
{ProductImport} = require '../lib'
Config = require '../config'
Promise = require 'bluebird'
{ExtendedLogger} = require 'sphere-node-utils'
package_json = require '../package.json'
sampleImportJson = require '../samples/import.json'

frozenTimeStamp = new Date().getTime()

cleanup = (logger, client) ->
  debug "Deleting old product entries..."
  client.products.all().fetch()
  .then (result) ->
    Promise.all _.map result.body.results, (e) ->
      client.products.byId(e.id).delete(e.version)
  .then (results) ->
    debug "#{_.size results} deleted."
    Promise.resolve()


describe 'Product import integration tests', ->

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
    .then ->
      # TODO: ensure that productType, taxCategory and categories
      # are created before running the tests
      done()
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
        @client.productProjections.where(predicate).staged(true).fetch()
      .then (result) ->
        fetchedProduct = result.body.results
        expect(_.size fetchedProduct[0].variants).toBe _.size sampleImport.products[0].variants
        expect(fetchedProduct[0].name).toEqual sampleImport.products[0].name
        expect(fetchedProduct[0].slug).toEqual sampleImport.products[0].slug
        done()
      .catch done
    , 10000

    it 'should do nothing for empty products list', (done) ->
      @import._processBatches([])
      .then =>
        expect(@import._summary.created).toBe 0
        expect(@import._summary.updated).toBe 0
        done()
      .catch done
    , 10000

    it 'should generate missing slug', (done) ->
      sampleImport = _.deepClone(sampleImportJson)
      delete sampleImport.products[0].slug
      delete sampleImport.products[1].slug

      spyOn(@import, "_generateUniqueToken").andReturn("#{frozenTimeStamp}")
      @import._processBatches(sampleImport.products)
      .then =>
        expect(@import._summary.created).toBe 2
        expect(@import._summary.updated).toBe 0
        predicate = "masterVariant(sku=\"#{sampleImport.products[0].masterVariant.sku}\")"
        @client.productProjections.where(predicate).staged(true).fetch()
      .then (result) ->
        fetchedProduct = result.body.results
        expect(fetchedProduct[0].slug.en).toBe "product-sync-test-product-1-#{frozenTimeStamp}"
        done()
      .catch done
    , 10000

    it 'should update existing product',  (done) ->
      sampleImport = _.deepClone(sampleImportJson)
      sampleUpdateRef = _.deepClone(sampleImportJson)
      sampleUpdate = _.deepClone(sampleImportJson)
      sampleUpdate.products = _.without(sampleUpdateRef.products,sampleUpdateRef.products[1])
      sampleUpdate.products[0].variants = _.without(sampleUpdateRef.products[0].variants,sampleUpdateRef.products[0].variants[1])
      sampleImport.products[0].name.de = 'Product_Sync_Test_Product_1_German'
      sampleAttribute1 =
        name: 'product_id'
        value: 'sampe_product_id1'
      sampleImport.products[0].masterVariant.attributes.push(sampleAttribute1)
      sampleImport.products[0].variants[0].attributes.push(sampleAttribute1)
      samplePrice =
        value:
          centAmount: 666
          currencyCode: 'JPY'
        country: 'JP'
      sampleImport.products[0].variants[0].prices = [samplePrice]

      @import._processBatches(sampleUpdate.products)
      .then =>
        expect(@import._summary.created).toBe 1
        @import._resetSummary()
        @import._resetCache()
        @import._processBatches(sampleImport.products)
      .then =>
        expect(@import._summary.created).toBe 1
        expect(@import._summary.updated).toBe 1
        predicate = "masterVariant(sku=\"#{sampleUpdate.products[0].masterVariant.sku}\")"
        @client.productProjections.where(predicate).staged(true).fetch()
      .then (result) ->
        expect(_.size result.body.results[0].variants).toBe 2
        done()
      .catch (err) -> done(_.prettify err.body)
    , 10000


