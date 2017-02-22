debug = require('debug')('spec:it:sphere-product-import')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
{ProductImport} = require '../lib'
ClientConfig = require '../config'
Promise = require 'bluebird'
path = require 'path'
fs = require 'fs-extra'
jasmine = require 'jasmine-node'
{ExtendedLogger} = require 'sphere-node-utils'
package_json = require '../package.json'
sampleImportJson = require '../samples/import.json'
sampleProductType = require '../samples/sample-product-type.json'
sampleType = require '../samples/sample-type.json'
sampleCategory = require '../samples/sample-category.json'
sampleTaxCategory = require '../samples/sample-tax-category.json'

frozenTimeStamp = new Date().getTime()


cleanup = (logger, client) ->
  debug "Deleting old product entries..."
  client.products.all().fetch()
  .then (result) ->
    unpublishProduct = (product) =>
      if product.masterData.current.published
        debug "unpublish product #{product.id}"
        return client.products.byId(product.id).update({
          version: product.version,
          actions: [
            { action: 'unpublish' }
          ]
        })
      else
        return Promise.resolve(product)
    Promise.map result.body.results, (e) =>
      unpublishProduct(e)
      .then (response) =>
        client.products.byId(response.id).delete(response.version)
  .then (results) ->
    debug "#{_.size results} products deleted."
    client.productTypes.where('name="Sample Product Type"').fetch()
  .then (result) ->
    Promise.map result.body.results, (e) ->
      client.productTypes.byId(e.id).delete(e.version)
  .then (result) ->
    debug "#{_.size result} product type(s) deleted."
    Promise.resolve()

ensureResource = (service, predicate, sampleData) ->
  debug 'Ensuring existence for: %s', predicate
  service.where(predicate).fetch()
  .then (result) ->
    if result.statusCode is 200 and result.body.count is 0
      service.create(sampleData)
      .then (result) ->
        debug "Sample #{JSON.stringify(result.body.name, null, 2)} created with id: #{result.body.id}"
        Promise.resolve()
    else
      Promise.resolve()

describe 'Product import integration tests', ->

  beforeEach (done) ->
    @logger = new ExtendedLogger
      additionalFields:
        project_key: ClientConfig.config.project_key
      logConfig:
        name: "#{package_json.name}-#{package_json.version}"
        streams: [
          { level: 'info', stream: process.stdout }
        ]

    errorDir = path.join(__dirname, '../errors')
    fs.emptyDirSync(errorDir)

    Config =
      clientConfig: ClientConfig
      errorDir: errorDir
      errorLimit: 30
      ensureEnums: true
      blackList: ['prices']
      filterUnknownAttributes: true

    @import = new ProductImport @logger, Config

    @client = @import.client

    @logger.info 'About to setup...'
    cleanup(@logger, @client)
    .then => ensureResource(@client.productTypes, 'name="Sample Product Type"', sampleProductType)
    .then => ensureResource(@client.categories, 'name(en="Snowboard equipment")', sampleCategory)
    .then => ensureResource(@client.taxCategories, 'name="Standard tax category"', sampleTaxCategory)
    .then => ensureResource(@client.types, "key=\"#{sampleType.key}\"", sampleType)
    .then ->
      done()
    .catch (err) -> done(_.prettify err)
  , 10000 # 10sec

  afterEach (done) ->
    @logger.info 'About to cleanup...'
    cleanup(@logger, @client)
    .then -> done()
    .catch (err) -> done(_.prettify err)
  , 10000 # 10sec


  it ' should import two new products', (done) ->
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
      predicate = "masterVariant(sku=#{JSON.stringify(sampleImport.products[0].masterVariant.sku)})"
      @client.productProjections.where(predicate).staged(true).fetch()
    .then (result) ->
      fetchedProduct = result.body.results
      expect(_.size fetchedProduct[0].variants).toBe _.size sampleImport.products[0].variants
      expect(fetchedProduct[0].name).toEqual sampleImport.products[0].name
      expect(fetchedProduct[0].slug).toEqual sampleImport.products[0].slug
      done()
    .catch done
  , 10000

  it ' should do nothing for empty products list', (done) ->
    @import._processBatches([])
    .then =>
      expect(@import._summary.created).toBe 0
      expect(@import._summary.updated).toBe 0
      done()
    .catch done
  , 10000

  it ' should generate missing slug', (done) ->
    sampleImport = _.deepClone(sampleImportJson)
    delete sampleImport.products[0].slug
    delete sampleImport.products[1].slug

    spyOn(@import, "_generateUniqueToken").andReturn("#{frozenTimeStamp}")
    @import._processBatches(sampleImport.products)
    .then =>
      expect(@import._summary.created).toBe 2
      expect(@import._summary.updated).toBe 0
      predicate = "masterVariant(sku=#{JSON.stringify(sampleImport.products[0].masterVariant.sku)})"
      @client.productProjections.where(predicate).staged(true).fetch()
    .then (result) ->
      fetchedProduct = result.body.results
      expect(fetchedProduct[0].slug.en).toBe "product-sync-test-product-1-#{frozenTimeStamp}"
      done()
    .catch done
  , 10000

  it ' should update existing product',  (done) ->
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

    spyOn(@import.sync, 'buildActions').andCallThrough()
    @import._processBatches(sampleUpdate.products)
    .then =>
      expect(@import._summary.created).toBe 1
      @import._resetSummary()
      @import._resetCache()
      @import._processBatches(sampleImport.products)
    .then =>
      expect(@import._summary.created).toBe 1
      expect(@import._summary.updated).toBe 1
      expect(@import.sync.buildActions).toHaveBeenCalledWith(jasmine.any(Object), jasmine.any(Object), ['sample_attribute_1'])
      predicate = "masterVariant(sku=#{JSON.stringify(sampleImport.products[0].masterVariant.sku)})"
      @client.productProjections.where(predicate).staged(true).fetch()
    .then (result) ->
      expect(_.size result.body.results[0].variants).toBe 2
      done()
    .catch (err) -> done(_.prettify err.body)
  , 10000

  it ' should continue on error - duplicate slug', (done) ->
    # FIXME: looks like the API doesn't correctly validate for duplicate slugs
    # for 2 concurrent requests (this happens randomly).
    # For now we have to test it as 2 separate imports.
    sampleImport = _.deepClone sampleImportJson
    @import._processBatches([sampleImport.products[0]])
    .then =>
      expect(@import._summary.created).toBe
      sampleImport2 = _.deepClone sampleImportJson
      sampleImport2.products[1].slug.en = 'product-sync-test-product-1'
      @import._resetSummary()
      @import._processBatches([sampleImport2.products[1]])
    .then =>
      # import should fail because product 1 has same slug
      expect(@import._summary.failed).toBe 1
      expect(@import._summary.created).toBe 0
      errorJson = require path.join(@import.errorDir,'error-1.json')
      expect(errorJson.body.errors.length).toBe 1

      error = errorJson.body.errors[0]
      expect(error.code).toEqual "DuplicateField"
      expect(error.duplicateValue).toEqual "product-sync-test-product-1"
      expect(error.field).toEqual "slug.en"
      done()
    .catch done

  it ' should continue of error - missing product name', (done) ->
    cleanup(@logger, @client)
    .then => ensureResource(@client.productTypes, 'name="Sample Product Type"', sampleProductType)
    .then =>
      sampleImport = _.deepClone sampleImportJson
      delete sampleImport.products[1].name
      delete sampleImport.products[1].slug
      @import._processBatches(sampleImport.products)
      .then =>
        expect(@import._summary.failed).toBe 1
        expect(@import._summary.created).toBe 1
        done()
      .catch done
  , 10000

  it ' should handle set type attributes correctly', (done) ->
    sampleImport = _.deepClone sampleImportJson

    setTextAttribute =
      name: 'sample_set_text'
      value: ['text_1', 'text_2']

    setTextAttributeUpdated =
      name: 'sample_set_text'
      value: ['text_1', 'text_2', 'text_3']

    sampleImport.products[0].masterVariant.attributes.push setTextAttribute

    predicate = "masterVariant(sku=#{JSON.stringify("eqsmlg-9'2\"\"")})"
    @import._processBatches(sampleImport.products)
    .then =>
      expect(@import._summary.created).toBe 2
      @client.productProjections.where(predicate).staged(true).fetch()
    .then (result) =>
      expect(result.body.results[0].masterVariant.attributes[0].value).toEqual setTextAttribute.value
      sampleUpdate = _.deepClone sampleImportJson
      sampleUpdate.products[0].masterVariant.attributes.push setTextAttributeUpdated
      @import._processBatches(sampleUpdate.products)
    .then =>
      expect(@import._summary.updated).toBe 1
      @client.productProjections.where(predicate).staged(true).fetch()
    .then (result) ->
      expect(result.body.results[0].masterVariant.attributes[0].value).toEqual setTextAttributeUpdated.value
      done()
    .catch done
  , 10000

  it ' should filter unknown attributes and import product without errors', (done) ->
    sampleImport = _.deepClone sampleImportJson

    unknownAttribute =
      name: 'unknownAttribute'
      value: 'unknown value'

    sampleImport.products[0].masterVariant.attributes.push unknownAttribute

    @import._processBatches(sampleImport.products)
    .then =>
      expect(@import._summary.created).toBe 2
      expect(@import._summary.unknownAttributeNames).toEqual ['unknownAttribute']
      done()
    .catch done
  , 10000

  it ' should update/create product with a new enum key', (done) ->
    @logger.info ':: should update/create product with a new enum key'
    sampleImport = _.deepClone sampleImportJson

    existingEnumKeyAttr =
      name: 'sample_enum_attribute'
      value: 'enum-1-key'

    newEnumKeyAttr =
      name: 'sample_enum_attribute'
      value: 'enum-new-key'

    expectedNewEnumKeyAttr =
      name: 'sample_enum_attribute'
      value:
        key: 'enum-new-key'
        label: 'enum-new-key'

    newEnumKeyAttr2 =
      name: 'sample_enum_attribute'
      value: 'enum-3-new-key'

    expectedNewEnumKeyAttr2 =
      name: 'sample_enum_attribute'
      value:
        key: 'enum-3-new-key'
        label: 'enum-3-new-key'

    sampleImport.products[0].masterVariant.attributes.push(existingEnumKeyAttr)
    sampleImport.products[0].masterVariant.attributes.push(newEnumKeyAttr)
    sampleImport.products[0].masterVariant.attributes.push(newEnumKeyAttr2)
    sampleImport.products[1].variants[0].attributes.push(existingEnumKeyAttr)
    sampleImport.products[1].variants[0].attributes.push(newEnumKeyAttr)

    predicate = "masterVariant(sku=#{JSON.stringify("eqsmlg-9'2\"\"")})"

    @import._processBatches(sampleImport.products)
    .then =>
      expect(@import._summary.created).toBe 2
      @client.productProjections.where(predicate).staged(true).fetch()
    .then (result) ->
      filterPredicate1 = (element) -> _.isEqual(element,expectedNewEnumKeyAttr)
      filterPredicate2 = (element) -> _.isEqual(element,expectedNewEnumKeyAttr2)
      expect(_.find(result.body.results[0].masterVariant.attributes, filterPredicate1)).toBeDefined()
      expect(_.find(result.body.results[0].masterVariant.attributes, filterPredicate2)).toBeDefined()
      done()
    .catch done


  it ' should create product with custom price attributes', (done) ->
    @logger.info ':: should create product with custom price attributes'
    product = _.deepClone sampleImportJson.products[0]
    predicate = "masterVariant(sku=#{JSON.stringify(product.masterVariant.sku)})"
    prices = [
      value:
        currencyCode: "EUR",
        centAmount: 329,
      country: "DE",
      validFrom: "2016-10-08T00:00:00.000Z",
      validUntil: "9999-12-31T00:00:00.000Z",
      custom:
        type:
          typeId: "type",
          id: sampleType.key,
        fields:
          custom1: 20161008063011,
          custom2: "string",
    ]

    # inject prices with custom fields
    product.masterVariant.prices = prices
    product.variants[0].prices = prices
    product.variants[1].prices = prices

    @import._processBatches([product])
    .then =>
      expect(@import._summary.created).toBe 1
      @client.productProjections.where(predicate).staged(true).fetch()
    .then (result) ->
      expectedFields = prices[0].custom.fields
      savedFields = result.body.results[0].masterVariant.prices[0].custom.fields
      expect(savedFields).toEqual(expectedFields)
      done()
    .catch done


  it ' should throw an error when importing non existing price reference', (done) ->
    @logger.info ':: should throw an error when importing non existing price reference'
    product = _.deepClone sampleImportJson.products[0]
    errorLogger = null
    errorCount = 0
    error = null
    prices = [
      value:
        currencyCode: "EUR",
        centAmount: 329,
      country: "DE",
      validFrom: "2016-10-08T00:00:00.000Z",
      validUntil: "9999-12-31T00:00:00.000Z",
      custom:
        type:
          typeId: "type",
          id: "wrong-price-reference",
        fields:
          custom1: 20161008063011,
          custom2: "string",
    ]

    # inject prices with custom fields
    product.masterVariant.prices = prices
    @import.errorCallback = (r, logger) ->
      errorLogger = logger
      errorCount += 1
      error = r.reason().toString()

    @import._processBatches([product])
    .then =>
      expectedError = "Didn\'t find any match while resolving types (key=\"#{prices[0].custom.type.id}\")"
      expect(@import._summary.failed).toBe 1
      expect(errorCount).toBe 1
      expect(error).toBe expectedError
      expect(_.isObject(errorLogger)).toBe true
      done()
    .catch done

