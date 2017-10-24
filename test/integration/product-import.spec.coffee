os = require 'os'
path = require 'path'
debug = require('debug')('spec:it:sphere-product-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
Promise = require 'bluebird'
{ ExtendedLogger } = require 'sphere-node-utils'
{ ProductImport } = require '../../lib'
ClientConfig = require '../../config'
{ deleteProductById } = require './test-helper'
package_json = require '../../package.json'

jasmine.getEnv().defaultTimeoutInterval = 30000

sampleProductTypeForProduct =
  name: 'productTypeForProductImport'
  description: 'test description'

bigProductType =
  name: 'bigProductType'
  description: 'test big poroductType description'
  attributes: [1..1031].map (i) ->
    name: "attr_#{i}"
    label:
      en: "Attribute #{i}"
    isRequired: false
    type:
      name: 'number'

createProduct = ->
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

    @fetchProducts = (productTypeId) =>
      @client.productProjections.staged(true)
        .all()
        .where("productType(id=\"#{productTypeId}\")")
        .fetch()

    logger.info 'About to setup...'
    cleanProducts(logger, @client)
    .then => ensureResource(@client.productTypes, 'name="productTypeForProductImport"', sampleProductTypeForProduct)
    .then (@productType) => ensureResource(@client.customerGroups, 'name="test-group"', sampleCustomerGroup)
    .then (@customerGroup) => ensureResource(@client.channels, 'key="test-channel"', sampleChannel)
    .then (@channel) =>
      ensureResource(@client.categories, 'externalId="test-category"', sampleCategory)
    .then (@category) =>
      done()
    .catch (err) ->
      done(_.prettify err)

  afterEach (done) ->
    logger.info 'About to cleanup...'
    cleanProducts(logger, @client)
      .then => cleanup(logger, @client.productTypes, @productType.id)
      .then => cleanup(logger, @client.customerGroups, @customerGroup.id)
      .then => cleanup(logger, @client.channels, @channel.id)
      .then => cleanup(logger, @client.categories, @category.id)
      .then -> done()
      .catch (err) -> done(_.prettify err)

  cleanProducts = (logger, client) ->
    client.productProjections.staged(true)
      .all()
      .fetch()
      .then (result) ->
        Promise.map result.body.results, (result) ->
          deleteProductById(logger, client, result.id)

  cleanup = (logger, service, id) ->
    service.byId(id).fetch()
    .then (result) ->
      service.byId(id).delete(result.body.version)

  it 'should handle an empty import', (done) ->
    @import.performStream([], -> {})
    .then =>
      @fetchProducts(@productType.id)
    .then (result) ->
      expect(result.body.results.length).toBe(0)
      done()

  it 'should not import products when they do not have SKUs', (done) ->
    productDraft = createProduct()[0]
    productDraft.variants[0].id = 2
    delete productDraft.variants[0].sku

    @import.performStream([productDraft], -> {})
    .then =>
      @fetchProducts(@productType.id)
    .then (result) =>
      expect(result.body.results.length).toBe(0)
      expect(@import._summary.productsWithMissingSKU).toBe(1)
      done()

  it 'should skip and continue on category not found', (done) ->
    productDrafts = createProduct()
    @import.performStream(productDrafts, -> {})
    .then =>
      @fetchProducts(@productType.id)
      .then (result) ->
        expect(result.body.results.length).toBe(2)
        done()

  it 'should import and update products with duplicate attributes', (done) ->
    productType = null

    productDraft = createProduct()[0]
    productDraft.productType.id = bigProductType.name

    productDraftClone = _.deepClone(productDraft)
    productDraftClone.masterVariant.attributes = []
    productDraftClone.variants[0].attributes = []

    productDraftClone.masterVariant.attributes.push
      name: 'attr_1'
      value: 1
    productDraftClone.masterVariant.attributes.push
      name: 'attr_1'
      value: 2

    productDraftClone.variants[0].attributes.push
      name: 'attr_1'
      value: 1

    ensureResource(@client.productTypes, "name=\"#{bigProductType.name}\"", bigProductType)
    .then (_productType) =>
      productType = _productType
      @import.performStream([productDraftClone], _.noop)
    .then =>
      @fetchProducts(productType.id)
    .then (result) =>
      expect(result.body.results.length).toBe(1)
      product = result.body.results[0]

      expect(product.masterVariant.attributes.length).toBe(1)
      expect(product.variants[0].attributes.length).toBe(1)

      # should take first value from duplicate attributes
      expect(product.masterVariant.attributes[0].name).toBe('attr_1')
      expect(product.masterVariant.attributes[0].value).toBe(1)

      expect(product.variants[0].attributes[0].name).toBe('attr_1')
      expect(product.variants[0].attributes[0].value).toBe(1)

      productDraft.masterVariant.attributes = [5..10].map (i) ->
        name: "attr_1"
        value: i

      @import.performStream([productDraft], _.noop)
    .then =>
      @fetchProducts(productType.id)
    .then (result) ->
      expect(result.body.results.length).toBe(1)
      product = result.body.results[0]

      expect(product.masterVariant.attributes.length).toBe(1)
      expect(product.masterVariant.attributes[0].name).toBe('attr_1')
      expect(product.masterVariant.attributes[0].value).toBe(5)
      done()
    .catch done

  it 'should fail on duplicate attribute', (done) ->
    productType = null
    configLocal = _.deepClone(config)
    configLocal.errorDir = path.join(os.tmpdir(), 'errors')
    importer = new ProductImport logger, configLocal
    importer.failOnDuplicateAttr = true

    productDraft = createProduct()[0]
    productDraft.productType.id = bigProductType.name
    productDraft.masterVariant.attributes = []
    productDraft.masterVariant.attributes.push
      name: 'attr_1'
      value: 1
    productDraft.masterVariant.attributes.push
      name: 'attr_1'
      value: 2

    ensureResource(@client.productTypes, "name=\"#{bigProductType.name}\"", bigProductType)
    .then (_productType) ->
      productType = _productType
      importer.performStream([productDraft], _.noop)
    .then ->
      expect(importer._summary.failed).toBe(1)
      errorJson = require path.join(importer._summary.errorDir, 'error-1.json')
      expect(errorJson.message).toBe('Variant with SKU \'sku1\' has duplicate attributes with name \'attr_1\'.')
      done()
    .catch done

  it 'should import and update large products', (done) ->
    productType = null

    productDraft = createProduct()[0]
    productDraft.productType.id = bigProductType.name

    productDraftClone = _.deepClone(productDraft)
    productDraftClone.variants[1].attributes = []
    productDraftClone.variants[1].attributes.push
      name: 'attr_1'
      value: 1

    ensureResource(@client.productTypes, "name=\"#{bigProductType.name}\"", bigProductType)
    .then (_productType) =>
      productType = _productType
      @import.performStream([productDraftClone], _.noop)
    .then =>
      productDraft.masterVariant.attributes = [1..1031].map (i) ->
        name: "attr_#{i}"
        value: i

      productDraft.variants[0].attributes = [1..200].map (i) ->
        name: "attr_#{i}"
        value: i

      @import.performStream([productDraft], _.noop)
    .then =>
      @fetchProducts(productType.id)
      .then (result) ->
        expect(result.body.results.length).toBe(1)
        product = result.body.results[0]

        expect(product.masterVariant.attributes.length).toBe(1031)
        expect(product.variants.length).toBe(2)
        expect(product.variants[0].attributes.length).toBe(200)
        expect(product.variants[1].attributes.length).toBe(0)
        done()

  it 'should update large products and handle concurrentModification error', (done) ->
    productType = null
    productDraft = createProduct()[0]
    productDraft.productType.id = bigProductType.name

    spy = spyOn(@import.client.products, 'update').andCallFake ->
      spy.andCallThrough() # next time call through

      # return 409 - concurrentModification error code
      Promise.reject
        statusCode: 409

    ensureResource(@client.productTypes, "name=\"#{bigProductType.name}\"", bigProductType)
    .then (_productType) =>
      productType = _productType
      productDraftClone = _.deepClone(productDraft)
      @import.performStream([productDraftClone], _.noop)
    .then =>
      productDraft.masterVariant.attributes = [1..900].map (i) ->
        name: "attr_#{i}"
        value: i

      productDraft.variants[0].attributes = [1..635].map (i) ->
        name: "attr_#{i}"
        value: i
      @import.performStream([productDraft], _.noop)
    .then =>
      @fetchProducts(productType.id)
      .then (result) ->
        expect(result.body.results.length).toBe(1)
        product = result.body.results[0]

        expect(product.masterVariant.attributes.length).toBe(900)
        expect(product.variants[0].attributes.length).toBe(635)
        done()

  describe 'product variant reassignment', ->
    beforeEach (done) ->
      @import = new ProductImport logger, config
      @import.variantReassignmentOptions = { enabled: true }
      done()

    it 'should reassign product variants', (done) ->
      productDraft1 = createProduct()[0]
      productDraft1.productType.id = @productType.id
      productDraft1.categories[0].id = @category.id
      productDraft2 = createProduct()[1]
      productDraft2.productType.id = @productType.id
      productDraft2.categories[0].id = @category.id
      Promise.all([
        ensureResource(@client.products, "masterData(staged(slug(en=\"#{productDraft1.slug.en}\")))", productDraft1)
        ensureResource(@client.products, "masterData(staged(slug(en=\"#{productDraft2.slug.en}\")))", productDraft2)
      ])
      .then () =>
        productDraftChunk = {
          productType:
            typeId: 'product-type'
            id: @productType.name
          "name": {
            "en": "reassigned-product"
          },
          "categories": [
            {
              "typeId": "category",
              "id": "test-category"
            }
          ],
          "categoryOrderHints": {},
          "slug": {
            "en": "reassigned-product"
          },
          "masterVariant": {
            "sku": "sku4",
            "prices": [],
            "images": [],
            "attributes": [],
            "assets": []
          },
          "variants": [
            {
              "sku": "sku3",
              "prices": [
                {
                  "value": {
                    "currencyCode": "GBP",
                    "centAmount": 9
                  },
                  "id": "e9748681-e42f-45c4-b07f-48b92c6e910a"
                }
              ],
              "images": [],
              "attributes": [],
              "assets": []
            }
          ],
          "searchKeywords": {}
        }
        @import.performStream([productDraftChunk], Promise.resolve)
      .then =>
        @fetchProducts(@productType.id)
      .then ({ body: { results } }) =>
        expect(results.length).toEqual(3)
        reassignedProductNoCategory = _.find results, (p) => p.name.en == 'reassigned-product'
        expect(reassignedProductNoCategory.slug.en).toEqual('reassigned-product')
        expect(reassignedProductNoCategory.masterVariant.sku).toEqual('sku4')
        expect(reassignedProductNoCategory.variants.length).toEqual(1)
        expect(reassignedProductNoCategory.variants[0].sku).toEqual('sku3')

        fooProduct = _.find results, (p) => p.name.en == 'foo'
        expect(fooProduct.slug.en).toEqual('foo')
        expect(fooProduct.masterVariant.sku).toEqual('sku1')
        expect(fooProduct.variants.length).toEqual(1)
        expect(fooProduct.variants[0].sku).toEqual('sku2')

        anonymizedProduct = _.find results, (p) => p.name.en == 'no-category'
        expect(anonymizedProduct.slug.ctsd).toBeDefined()
        expect(anonymizedProduct.variants.length).toEqual(1)
        skus = anonymizedProduct.variants.concat(anonymizedProduct.masterVariant)
          .map((v) => v.sku)
        expect(skus).toContain('sku5')
        expect(skus).toContain('sku6')
        done()
      .catch (err) =>
        done(_.prettify err)
