debug = require('debug')('spec:it:sphere-product-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
{PriceImport} = require '../../lib'
Config = require '../../config'
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

getOrCreateProductType = (client) ->
  new Promise (resolve, reject) ->
    name = 'productTypeForPriceImport'
    client.productTypes.where("name=\"#{name}\"").fetch()
    .then (result) ->
      if result.body.total is 0
        pt =
          name: name
          description: 'bla bla'
        client.productTypes.create(pt)
        .then (res) -> resolve res.body
      else
        resolve result.body.results[0]

createProduct = (client, productType) ->
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
  client.products.create product

describe 'Price Importer integration tests', ->

  beforeEach (done) ->
    @logger = new ExtendedLogger
      additionalFields:
        project_key: Config.config.project_key
      logConfig:
        name: "#{package_json.name}-#{package_json.version}"
        streams: [
          { level: 'info', stream: process.stdout }
        ]

    @import = new PriceImport @logger, Config

    @client = @import.client

    @logger.info 'About to setup...'
    cleanup @logger, @client
    .then =>
      getOrCreateProductType @client
    .then (@productType) =>
      createProduct @client, @productType
    .then (@product) ->
      done()
    .catch (err) ->
      done(_.prettify err)
  , 30000 # 30sec

  afterEach (done) ->
    @logger.info 'About to cleanup...'
    cleanup(@logger, @client)
    .then -> done()
    .catch (err) -> done(_.prettify err)
  , 30000 # 30sec

  it 'should update prices of a product', (done) ->
    prices = [
      {
        sku: 'sku1'
        value:
          centAmount: 9999
          currencyCode: 'EUR'
      }
      {
        sku: 'sku2'
        value:
          centAmount: 666
          currencyCode: 'JPY'
        country: 'JP'
      }
    ]
    @import.performStream prices, (res) =>
      expect(res).toBeUndefined()
      @client.productProjections.staged(true).all().fetch()
      .then (res) ->
        expect(_.size res.body.results).toBe 1
        product = res.body.results[0]
        expect(_.size product.masterVariant.prices).toBe 1
        expect(product.masterVariant.prices[0].value.centAmount).toBe 9999
        expect(product.masterVariant.prices[0].value.currencyCode).toBe 'EUR'
        expect(_.size product.variants[0].prices).toBe 1
        expect(product.variants[0].prices[0].value.centAmount).toBe 666
        expect(product.variants[0].prices[0].value.currencyCode).toBe 'JPY'
        expect(product.variants[0].prices[0].country).toBe 'JP'
        expect(_.size product.variants[1].prices).toBe 1
        expect(product.variants[1].prices[0].value.centAmount).toBe 9
        expect(product.variants[1].prices[0].value.currencyCode).toBe 'GBP'
        done()
      .catch (err) ->
        done(_.prettify err)
  , 30000
