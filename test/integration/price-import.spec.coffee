debug = require('debug')('spec:it:sphere-product-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
{PriceImport} = require '../../lib'
ClientConfig = require '../../config'
Promise = require 'bluebird'
{ExtendedLogger} = require 'sphere-node-utils'
package_json = require '../../package.json'

cleanup = (logger, client) ->
  debug "Deleting old product entries..."
  client.products.all().fetch()
  .then (result) ->
    Promise.all _.map result.body.results, (e) ->
      client.products.byId(e.id).delete(e.version)
  .then (results) ->
    debug "#{_.size results} deleted."
    Promise.resolve()

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
    cleanup logger, @client
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
    cleanup(logger, @client)
    .then -> done()
    .catch (err) -> done(_.prettify err)
  , 30000 # 30sec

  it 'should update prices of a product', (done) ->

    @import.performStream _.deepClone(prices), (res) =>
      expect(res).toBeUndefined()
      @client.productProjections.staged(true).all().fetch()
      .then (res) =>
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

  it 'should update prices and publish the product', (done) ->

    @import.publishingStrategy = 'stagedAndPublishedOnly'

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