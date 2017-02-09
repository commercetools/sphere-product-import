debug = require('debug')('spec:it:sphere-product-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
{ ExtendedLogger } = require 'sphere-node-utils'
{ ProductImport } = require '../../lib'
ClientConfig = require '../../config'
{ deleteProductById } = require './test-helper'
package_json = require '../../package.json'

sampleProductTypeForProduct =
  name: 'productTypeForProductImport'
  description: 'test description'

createProduct = () ->
  [
    {
      productType:
        typeId: 'product-type'
        id: 'productTypeForProductImport'
      name:
        en: 'foo'
      slug:
        en: 'foo'
      masterVariant:
        sku: 'sku1'
      variants: [
        {
          sku: 'sku2',
          prices: [{ value: { centAmount: 777, currencyCode: 'JPY' } }]
        }
        {
          sku: 'sku3',
          prices: [{ value: { centAmount: 9, currencyCode: 'GBP' } }]
        }
      ],
      categories: [
        {
          id: 'test-category'
        }
      ]
    },
    {
      productType:
        typeId: 'product-type'
        id: 'productTypeForProductImport'
      name:
        en: 'no-category'
      slug:
        en: 'no-category'
      masterVariant:
        sku: 'sku4'
      variants: [
        {
          sku: 'sku5',
          prices: [{ value: { centAmount: 777, currencyCode: 'JPY' } }]
        }
        {
          sku: 'sku6',
          prices: [{ value: { centAmount: 9, currencyCode: 'GBP' } }]
        }
      ],
      categories: [
        {
          id: 'not-existing-category'
        }
      ]
    },
    {
      productType:
        typeId: 'product-type'
        id: 'productTypeForProductImport'
      name:
        en: 'foo2'
      slug:
        en: 'foo2'
      masterVariant:
        sku: 'sku7'
      variants: [
        {
          sku: 'sku8',
          prices: [{ value: { centAmount: 777, currencyCode: 'JPY' } }]
        }
        {
          sku: 'sku9',
          prices: [{ value: { centAmount: 9, currencyCode: 'GBP' } }]
        }
      ],
      categories: [
        {
          id: 'test-category'
        }
      ]
    }
  ]

sampleCategory =
  name:
    en: 'Test category'
  slug:
    en: 'test-category'
  externalId: 'test-category'

sampleCustomerGroup =
  groupName: 'test-group'

sampleChannel =
  key: 'test-channel'

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

config =
  clientConfig: ClientConfig
  errorLimit: 0

describe 'Product Importer integration tests', ->

  beforeEach (done) ->
    @import = new ProductImport logger, config

    @client = @import.client

    logger.info 'About to setup...'
    ensureResource(@client.productTypes, 'name="productTypeForProductImport"', sampleProductTypeForProduct)
    .then (@productType) => ensureResource(@client.customerGroups, 'name="test-group"', sampleCustomerGroup)
    .then (@customerGroup) => ensureResource(@client.channels, 'key="test-channel"', sampleChannel)
    .then (@channel) =>
      ensureResource(@client.categories, 'externalId="test-category"', sampleCategory)
    .then (@category) =>
      done()
    .catch (err) ->
      done(_.prettify err)
  , 30000 # 30sec
  
  afterEach (done) ->
    logger.info 'About to cleanup...'
    @client.productProjections.staged(true)
      .all()
      .where("productType(id=\"#{@productType.id}\")")
      .fetch()
      .then (result) =>
        Promise.map result.body.results, (result) =>
          deleteProductById(logger, @client, result.id)
      .then => cleanup(logger, @client.productTypes, @productType.id)
      .then => cleanup(logger, @client.customerGroups, @customerGroup.id)
      .then => cleanup(logger, @client.channels, @channel.id)
      .then => cleanup(logger, @client.categories, @category.id)
      .then -> done()
      .catch (err) -> done(_.prettify err)
  , 30000 # 30sec
    

  cleanup = (logger, service, id) ->
    service.byId(id).fetch()
    .then (result) ->
      service.byId(id).delete(result.body.version)
    .then (result) ->
      Promise.resolve()
      
      
  it 'should skip and continue on category not found', (done) ->
    productDrafts = createProduct()
    @import.performStream(productDrafts, () => {})
    .then () =>
      @client.productProjections.staged(true)
      .all()
      .where("productType(id=\"#{@productType.id}\")")
      .fetch()
      .then (result) =>
        expect(result.body.results.length).toBe(2)
        done()
  , 30000

