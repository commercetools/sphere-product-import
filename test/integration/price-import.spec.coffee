debug = require('debug')('spec:it:sphere-product-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
{PriceImport} = require '../../lib'
ClientConfig = require '../../config'
{ ExtendedLogger } = require 'sphere-node-utils'
{ deleteProducts } = require './test-helper'
package_json = require '../../package.json'
testProduct = require '../resources/product.json'
testProductPrices = require '../resources/product-prices.json'

sampleProductTypeForPrice =
  name: 'productTypeForPriceImport'
  description: 'bla bla'

createProduct = (productType) ->
  product =
    productType:
      typeId: 'product-type'
      id: productType.id
    name:
      en: 'foo'
    slug:
      en: 'foo'
    masterVariant:
      sku: 'sku1'
    variants: [
      { sku: 'sku2', prices: [ { value: { centAmount: 777, currencyCode: 'JPY' } } ] }
      { sku: 'sku3', prices: [ { value: { centAmount: 9, currencyCode: 'GBP' } } ] }
    ]

sampleCustomerGroup =
  groupName: 'test-group'

sampleChannel =
  key: 'test-channel'

prices = [
  {
    sku: 'sku1'
    prices: [
      {
        value:
          centAmount: 9999
          currencyCode: 'EUR'
        customerGroup:
          id: 'test-group'
      },
      {
        value:
          centAmount: 7999
          currencyCode: 'EUR'
        customerGroup:
          id: 'test-group'
        channel:
          id: 'test-channel'
      }
    ]
  }
  {
    sku: 'sku2'
    prices: [
      {
        value:
          centAmount: 666
          currencyCode: 'JPY'
        country: 'JP'
        customerGroup:
          id: 'test-group'
      }
    ]
  }
]

ensureResource = (service, predicate, sampleData) ->
  debug 'Ensuring existence for: %s', predicate
  service.where(predicate).fetch()
  .then (result) ->
    if result.statusCode is 200 and result.body.count is 0
      service.create(sampleData)
      .then (result) ->
        debug "Sample #{predicate} created with id: #{result.body.id}"
        Promise.resolve(result.body)
    else
      Promise.resolve(result.body.results[0])

logger = new ExtendedLogger
  additionalFields:
    project_key: ClientConfig.config.project_key
  logConfig:
    name: "#{package_json.name}-#{package_json.version}"
    streams: [
      { level: 'error', stream: process.stderr },
      { level: 'debug', stream: process.stdout }
    ]

Config =
  clientConfig: ClientConfig
  errorLimit: 0

describe 'Price Importer integration tests', ->

  beforeEach (done) ->
    @import = new PriceImport logger, Config
    @client = @import.client

    logger.info 'About to setup...'
    deleteProducts logger, @client
    .then => ensureResource(@client.productTypes, 'name="productTypeForPriceImport"', sampleProductTypeForPrice)
    .then (@productType) => ensureResource(@client.customerGroups, 'name="test-group"', sampleCustomerGroup)
    .then (@customerGroup) => ensureResource(@client.channels, 'key="test-channel"', sampleChannel)
    .then (@channel) => ensureResource(@client.products, 'masterData(staged(name(en="foo")))', createProduct(@productType))
    .then (@product) =>
      logger.debug "product created with id: #{@product.id}"
      done()
    .catch (err) ->
      done(_.prettify err)
  , 30000 # 30sec

  afterEach (done) ->
    logger.info 'About to cleanup...'
    deleteProducts(logger, @client)
    .then -> done()
    .catch (err) -> done(_.prettify err)
  , 30000 # 30sec

  it 'should update prices of a product', (done) ->
    _prices = _.deepClone(prices)
    _prices.push
      sku: 'unknownSku'
      prices: [
        {
          value:
            centAmount: 6666
            currencyCode: 'EUR'
        }
      ]
    @import.performStream _prices, (res) =>
      expect(res).toBeUndefined()
      @client.productProjections.staged(true).all().fetch()
    .then (res) =>
      expect(@import._summary).toEqual
        unknownSKUCount: 1
        duplicatedSKUs: 0
        variantWithoutPriceUpdates: 1
        updated: 1
        failed: 0

      expect(_.size res.body.results).toBe 1
      product = res.body.results[0]
      expect(_.size product.masterVariant.prices).toBe 2
      expect(product.masterVariant.prices[0].customerGroup.id).toBe @customerGroup.id
      expect(product.masterVariant.prices[1].customerGroup.id).toBe @customerGroup.id
      expect(product.masterVariant.prices[1].channel.id).toBe @channel.id
      expect(product.masterVariant.prices[0].value.centAmount).toBe 9999
      expect(product.masterVariant.prices[0].value.currencyCode).toBe 'EUR'
      expect(_.size product.variants[0].prices).toBe 1
      expect(product.variants[0].prices[0].value.centAmount).toBe 666
      expect(product.variants[0].prices[0].value.currencyCode).toBe 'JPY'
      expect(product.variants[0].prices[0].country).toBe 'JP'
      expect(product.variants[0].prices[0].customerGroup.id).toBe @customerGroup.id
      expect(_.size product.variants[1].prices).toBe 1
      expect(product.variants[1].prices[0].value.centAmount).toBe 9
      expect(product.variants[1].prices[0].value.currencyCode).toBe 'GBP'
      done()
    .catch (err) ->
      done(_.prettify err.body)
  , 30000

  it 'should delete empty prices', (done) ->
    _prices = _.deepClone(prices)
    _prices[0].prices[1].value.centAmount = 1234
    # delete rest of prices
    _prices[0].prices[0].value.centAmount = ''
    _prices[1].prices[0].value.centAmount = ''
    _prices.push({
      sku: 'sku3',
      prices: [{
        value: {
          centAmount: '',
          currencyCode: 'GBP'
        }
      }]
    })

    @import.deleteOnEmpty = true
    @import.performStream _prices, (res) =>
      expect(res).toBeUndefined()
      @client.productProjections.staged(true).all().fetch()
    .then (res) =>
      expect(@import._summary).toEqual
        unknownSKUCount: 0
        duplicatedSKUs: 0
        variantWithoutPriceUpdates: 0
        updated: 1
        failed: 0

      expect(_.size res.body.results).toBe 1
      product = res.body.results[0]
      expect(_.size product.masterVariant.prices).toBe 1
      expect(product.masterVariant.prices[0].value.currencyCode).toBe 'EUR'
      expect(product.masterVariant.prices[0].value.centAmount).toBe 1234

      expect(_.size product.variants[0].prices).toBe 0
      expect(_.size product.variants[1].prices).toBe 0

      @import.deleteOnEmpty = false
      done()
    .catch (err) =>
      @import.deleteOnEmpty = false
      done(_.prettify err.body)
  , 30000

  it 'should update prices and publish the product', (done) ->
    @import.publishingStrategy = 'notStagedAndPublishedOnly'

    @client.products.byId(@product.id).update({
      version: @product.version,
      actions: [
        { action: 'publish' }
      ]
    })
    .then =>
      logger.info 'product published'
      @import.performStream _.deepClone(prices), (res) =>
        expect(res).toBeUndefined()
        @client.productProjections.staged(true).all().fetch()
    .then (res) =>
      @publishedProduct = res.body.results[0]
      expect(@publishedProduct.hasStagedChanges).toBeFalsy()
      expect(@publishedProduct.published).toBeTruthy()
    .catch (err) ->
      logger.error(err)
      done(_.prettify err.body)
    .finally =>
      logger.info 'un publishing the product'
      @client.products.byId(@publishedProduct.id).update({
        version: @publishedProduct.version,
        actions: [
          { action: 'unpublish' }
        ]
      })
      .then ->
        done()
  , 30000

  it 'should remove missing prices', (done) ->
    importer = new PriceImport logger, Config
    importer.preventRemoveActions = true # disable price removing

    _testProduct = _.deepClone(testProduct)
    _testProduct.productType.id = @productType.id
    logger.info 'importing test product'
    ensureResource(@client.products, "key=\"#{_testProduct.key}\"", _testProduct)
      .then () =>
        logger.info 'importing prices'
        importer.performStream [_.deepClone(testProductPrices)], _.noop
      .then =>
        @client.productProjections
          .staged(true)
          .where("key=\"#{_testProduct.key}\"")
          .fetch()
      .then (res) ->
        product = res.body.results[0]
        expect(product).toBeTruthy()
        expect(product.masterVariant.prices.length).toBe(3)
      .then ->
        done()
      .catch (err) ->
        done(_.prettify err)

  , 30000