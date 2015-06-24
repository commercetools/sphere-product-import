_ = require 'underscore'
_.mixin require 'underscore-mixins'
{ProductImport} = require '../lib'
Config = require '../config'
Promise = require 'bluebird'

frozenTimeStamp = new Date().getTime()

sampleProducts = [
    masterVariant:
      sku: 'a'
    variants: [
      id: 2
      sku: 'b'
    ,
      id: 3
    ,
      id: 4
      sku: 'c'
    ]
  ,
    masterVariant: {}
    variants: [
      id: 2
      sku: 'b'
    ,
      id: 3
      sku: 'd'
    ]
  ,
    masterVariant:
      sku: 'e'
    variants: []
]

sampleNewProduct =
  name:
    en: 'sample_product_name'
  productType:
    id: 'product_type_name'
  taxCategory:
    id: 'tax_category_name'
  categories: [
    id: 'category_external_id1'
  ,
    id: 'category_external_id2'
  ]

sampleMasterVariant =
  sku: '12345'
  id: 1
  attributes: [
     name: 'attribute1'
     value: 'attribute1_value1'
  ]
  images: []

sampleVariant1 =
  id: '2'
  sku: '12345_2'
  attributes: [
    name: 'attribute1'
    value: 'attribute1_value2'
  ]
  images: []


sampleVariant2 =
  id: '7'
  sku: '12345_7'
  attributes: [
    name: 'attribute1'
    value: 'attribute1_value3'
  ]
  images: []

sampleNewPreparedProduct =
  name:
    en: 'sample_product_name'

  slug:
    en: "sample-product-name-#{frozenTimeStamp}"

  productType:
    id: 'product_type_internal_id'
    typeId: 'product-type'

  taxCategory:
    id: 'tax_category_internal_id'
    typeId: 'tax-category'

  categories: [
    id: 'category_internal_id1'
    typeId: 'category'
  ,
    id: 'category_internal_id1'
    typeId: 'category'
  ]

sampleProductProjectionResponse = [
  masterVariant:
    sku: 'e'
  variants: []
]

sampleProductTypeResponse =
  body:
    results: [
      id: 'product_type_internal_id'
      version: 1
      name: 'AGS'
      description: 'Gütesiegel'
      classifier: 'Complex'
      attributes: [ ]
      createdAt: '2015-04-15T15:11:07.175Z'
      lastModifiedAt: '2015-04-15T15:11:07.175Z'
    ]

sampleTaxCategoryResponse =
  body:
    results: [
      id: 'tax_category_internal_id'
      version: 5
      name: 'defaultTax_AT'
      description: 'Steuer Österreich'
      rates: [
        name: '20% MwSt'
        amount: 0.2
        includedInPrice: true
        country: 'AT'
        id: '2CV8kXRE'
      ]
      createdAt: '2015-03-03T10:12:22.136Z'
      lastModifiedAt: '2015-04-16T07:36:36.123Z'
    ]

sampleCategoriesResponse =
  body:
    results: [
      id: 'category_internal_id1'
      version: 2
      name:
        de: 'obst-gemuse1'
      ancestors: []
      externalId: 'category_external_id1'
    ]

sampleReferenceCats =
  [
    id: 'category_external_id1'
  ,
    id: 'category_external_id2'
  ]

describe 'ProductImport', ->

  beforeEach ->
    @import = new ProductImport null, Config

  it 'should initialize', ->
    expect(@import).toBeDefined()
    expect(@import.client).toBeDefined()
    expect(@import.client.constructor.name).toBe 'SphereClient'
    expect(@import.sync).toBeDefined()
    expect(@import.sync.constructor.name).toBe 'ProductSync'


  describe '::performStream', ->

    it 'should execute callback after finished processing batches', (done) ->
      spyOn(@import, '_processBatches').andCallFake -> Promise.resolve()
      @import.performStream [1,2,3], done
      .catch (err) -> done(_.prettify err)


  describe '::_extractUniqueSkus', ->

    it 'should extract 5 unique skus from master and variants', ->
      skus = @import._extractUniqueSkus(sampleProducts)
      expect(skus.length).toBe 5
      expect(skus).toEqual ['a', 'b', 'c', 'd', 'e']

  describe '::_createProductFetchBySkuQueryPredicate', ->

    it 'should return predicate with 5 unique skus', ->
      skus = @import._extractUniqueSkus(sampleProducts)
      predicate = @import._createProductFetchBySkuQueryPredicate(skus)
      expect(predicate).toEqual 'masterVariant(sku in ("a", "b", "c", "d", "e")) or variants(sku in ("a", "b", "c", "d", "e"))'

  describe '::_isExistingEntry', ->

    it 'should detect existing entries', ->
      existingProduct = sampleProducts[2]
      newProduct = sampleProducts[0]
      expect(@import._isExistingEntry(existingProduct,sampleProductProjectionResponse)).toBeDefined()
      expect(@import._isExistingEntry(existingProduct,sampleProductProjectionResponse).masterVariant.sku).toEqual "e"
      expect(@import._isExistingEntry(newProduct,sampleProductProjectionResponse)).toBeUndefined()

  describe '::_resolveReference', ->

    it 'should resolve product type reference and cache the result', (done) ->
      @import._resetCache()
      spyOn(@import.client.productTypes, "fetch").andCallFake -> Promise.resolve(sampleProductTypeResponse)
      productTypeRef = { id: 'AGS'}
      @import._resolveReference(@import.client.productTypes, 'productType', productTypeRef, "name=\"#{productTypeRef.id}\"")
      .then (result) =>
        expect(@import.client.productTypes.fetch).toHaveBeenCalled()
        expect(result).toEqual sampleProductTypeResponse.body.results[0].id
        expect(@import._cache.productType["AGS"]).toEqual sampleProductTypeResponse.body.results[0].id
        done()
      .catch done

    it 'should resolve tax category reference and cache the result', (done) ->
      @import._resetCache()
      spyOn(@import.client.taxCategories, "fetch").andCallFake -> Promise.resolve(sampleTaxCategoryResponse)
      taxCategoryRef = { id: 'defaultTax_AT' }
      @import._resolveReference(@import.client.taxCategories, 'taxCategory', taxCategoryRef, "name=\"#{taxCategoryRef.id}\"")
      .then (result) =>
        expect(@import.client.taxCategories.fetch).toHaveBeenCalled()
        expect(result).toEqual sampleTaxCategoryResponse.body.results[0].id
        expect(@import._cache.taxCategory["defaultTax_AT"]).toEqual sampleTaxCategoryResponse.body.results[0].id
        done()
      .catch done


    it 'should resolve list of category references and cache the result', (done) ->
      @import._resetCache()
      spyOn(@import.client.categories, "fetch").andCallFake -> Promise.resolve(sampleCategoriesResponse)
      categoryRef = { id: 'category_external_id1' }
      @import._resolveReference(@import.client.categories, 'categories', categoryRef, "externalId=\"#{categoryRef.id}\"")
      .then (result) =>
        expect(@import.client.categories.fetch).toHaveBeenCalled()
        expect(result).toEqual sampleCategoriesResponse.body.results[0].id
        expect(@import._cache.categories["category_external_id1"]).toEqual sampleCategoriesResponse.body.results[0].id
        done()
      .catch done


    it 'should resolve reference from cache', (done) ->
      @import._resetCache()
      @import._cache.taxCategory['defaultTax_AT'] = "tax_category_internal_id"
      spyOn(@import.client.taxCategories, "fetch").andCallFake -> Promise.resolve(sampleTaxCategoryResponse)
      taxCategoryRef = { id: 'defaultTax_AT' }
      @import._resolveReference(@import.client.taxCategories, 'taxCategory', taxCategoryRef, "name=\"#{taxCategoryRef.id}\"")
      .then (result) =>
        expect(@import.client.taxCategories.fetch).not.toHaveBeenCalled()
        expect(result).toEqual sampleTaxCategoryResponse.body.results[0].id
        expect(result.isRejected).toBeUndefined()
        done()
      .catch done


    it 'should throw error on undefined reference', (done) ->
      @import._resolveReference(@import.client.taxCategories, 'taxCategory', undefined , "name=\"#{taxCategoryRef?.id}\"")
      .then done
      .catch (err) ->
        expect(err).toBe 'Missing taxCategory'
        done()

  describe '::_resolveProductCategories', ->

    it 'should resolve a list of categories', (done) ->
      spyOn(@import, "_resolveReference").andCallFake -> Promise.resolve("foo")
      @import._resolveProductCategories(sampleReferenceCats)
      .then (result) =>
        expect(result.length).toBe 2
        expect(@import._resolveReference.calls.length).toBe 2
        expect(@import._resolveReference.calls[0].args[2]).toBe sampleReferenceCats[0]
        expect(@import._resolveReference.calls[1].args[2]).toBe sampleReferenceCats[1]
        expect(@import._resolveReference.calls[1].args[3]).toBe "externalId=\"category_external_id2\""
        expect(@import._resolveReference).toHaveBeenCalledWith(jasmine.any(Object), "categories", jasmine.any(Object), jasmine.any(String))
        done()
      .catch done

    it 'should resolve with empty array on undefined list of product category references', (done) ->
      @import._resolveProductCategories(undefined)
      .then (result) ->
        expect(result).toBe undefined
        done()
      .catch done

    it 'should resolve with empty array on empty list of product category references', (done) ->
      @import._resolveProductCategories([])
      .then (result) ->
        expect(result).toBe undefined
        done()
      .catch done

  describe '::_generateSlug', ->

    it 'should generate valid slug', ->
      sampleName =
        name:
          en: 'sample_product_name'
          de: 'sample_product_german_name'

      spyOn(@import, "_generateUniqueToken").andReturn("#{frozenTimeStamp}")
      slugs = @import._generateSlug(sampleName.name)
      expect(slugs.en).toBe "sample-product-name-#{frozenTimeStamp}"
      expect(slugs.de).toBe "sample-product-german-name-#{frozenTimeStamp}"


  describe '::_prepareNewProduct', ->

    beforeEach ->
      spyOn(@import, "_resolveReference").andCallFake (service, refKey, ref) ->
        switch refKey
          when "productType"
            if ref then Promise.resolve(sampleProductTypeResponse.body.results[0].id) else Promise.resolve()

          when "taxCategory"
            if ref then Promise.resolve(sampleTaxCategoryResponse.body.results[0].id) else Promise.resolve()

          when "categories"
            if ref then Promise.resolve("category_internal_id1") else Promise.resolve([])

      spyOn(@import, "_generateUniqueToken").andReturn("#{frozenTimeStamp}")


    it 'should resolve all references in the new product', (done) ->

      @import._prepareNewProduct(_.deepClone(sampleNewProduct))
      .then (result) =>
        expect(@import._resolveReference.calls.length).toBe 4
        expect(result).toEqual sampleNewPreparedProduct
        done()
      .catch done

    it 'should resolve all references in the new product without product type', (done) ->
      newProductWithoutProductType = _.deepClone(sampleNewProduct)
      delete newProductWithoutProductType.productType
      @import._prepareNewProduct(newProductWithoutProductType)
      .then (result) =>
        preparedWithoutProductType = _.deepClone(sampleNewPreparedProduct)
        delete preparedWithoutProductType.productType
        expect(result).toEqual preparedWithoutProductType
        expect(@import._resolveReference.calls.length).toBe 4
        expect(@import._resolveReference.calls[0].args[2]).toBe undefined
        done()
      .catch done

    it 'should resolve all references in the new product without product categories', (done) ->
      newProductWithoutProductCategories = _.deepClone(sampleNewProduct)
      delete newProductWithoutProductCategories.categories
      @import._prepareNewProduct(newProductWithoutProductCategories)
      .then (result) =>
        preparedWithoutProductCategories = _.deepClone(sampleNewPreparedProduct)
        delete preparedWithoutProductCategories.categories
        expect(result).toEqual preparedWithoutProductCategories
        expect(@import._resolveReference.calls.length).toBe 2
        done()
      .catch done

    it 'should resolve all references in the new product without tax category', (done) ->
      newProductWithoutTaxCategory = _.deepClone(sampleNewProduct)
      delete newProductWithoutTaxCategory.taxCategory
      @import._prepareNewProduct(newProductWithoutTaxCategory)
      .then (result) =>
        preparedWithoutTaxCategory = _.deepClone(sampleNewPreparedProduct)
        delete preparedWithoutTaxCategory.taxCategory
        expect(result).toEqual preparedWithoutTaxCategory
        expect(@import._resolveReference.calls.length).toBe 4
        expect(@import._resolveReference.calls[3].args[2]).toBe undefined
        done()
      .catch done

    xit 'should reject if name is missing', (done) ->
      newProductWithoutName = _.deepClone(sampleNewProduct)
      delete newProductWithoutName.name
      @import._prepareNewProduct(newProductWithoutName)
      .then done
      .catch (err) ->
        expect(err).toBe 'Product name is required.'
        done()


  describe '::_createOrUpdate', ->

    it 'should create a new product and update an existing product', (done) ->
      newProduct = _.deepClone(sampleNewPreparedProduct)
      newProduct.name = { en: "My new product" }
      newProduct.masterVariant = sampleMasterVariant
      newProduct.variants = [ sampleVariant1, sampleVariant2 ]

      existingProduct1 = _.deepClone(newProduct)
      existingProduct1.id = "existing_id1"
      existingProduct1.masterVariant.sku = "9876_1"
      existingProduct1.variants[0].sku = "9876_1_1"
      existingProduct1.variants[1].sku = "9876_1_2"

      existingProduct2 = _.deepClone(newProduct)
      existingProduct2.id = "existing_id2"
      existingProduct2.masterVariant.sku = "9876_2"
      existingProduct2.variants[0].sku = "9876_2_1"
      existingProduct2.variants[1].sku = "9876_2_2"
      existingProduct2.version = 1

      updateProduct = _.deepClone(existingProduct2)
      sampleVariant3 = _.deepClone(sampleVariant2)
      sampleVariant3.sku = "9876_2_3"
      sampleVariant3.id = "9"
      sampleVariant3.prices = []
      updateProduct.variants[2] = sampleVariant3

      existingProducts = [existingProduct1,existingProduct2]

      expectedUpdateActions =
        actions: [
          action: 'addVariant'
          sku: '9876_2_3'
          attributes: [
            name: 'attribute1'
            value: 'attribute1_value3'
          ],
          prices: []
        ],
        version: 1

      spyOn(@import, "_prepareNewProduct").andCallFake (prepareProduct) -> Promise.resolve(prepareProduct)
      spyOn(@import,"_prepareUpdateProduct").andCallFake (prepareProduct) -> Promise.resolve(prepareProduct)
      spyOn(@import.client._rest, 'POST').andCallFake (endpoint, payload, callback) ->
        callback(null, {statusCode: 200}, {})
      @import._createOrUpdate([newProduct,updateProduct],existingProducts)
      .then =>
        expect(@import._prepareNewProduct).toHaveBeenCalled()
        expect(@import.client._rest.POST.calls[0].args[1]).toEqual newProduct
        expect(@import.client._rest.POST.calls[1].args[1]).toEqual expectedUpdateActions
        done()
      .catch done


  describe '::_processBatches', ->

    it 'should process list of products in batches', (done) ->
      existingProducts = _.deepClone(sampleProducts)
      delete existingProducts[1]
      delete existingProducts[2]

      spyOn(@import, "_extractUniqueSkus").andCallThrough()
      spyOn(@import, "_createProductFetchBySkuQueryPredicate").andCallThrough()
      spyOn(@import.client.productProjections,"fetch").andCallFake -> Promise.resolve({body: {results: existingProducts}})
      spyOn(@import, "_createOrUpdate").andCallFake -> Promise.all([Promise.resolve({statusCode: 201}), Promise.resolve({statusCode: 200})])
      @import._processBatches(sampleProducts)
      .then =>
        expect(@import._extractUniqueSkus).toHaveBeenCalled()
        expect(@import._createProductFetchBySkuQueryPredicate).toHaveBeenCalled()
        expect(@import._summary).toEqual
          emptySKU: 2
          created: 1
          updated: 1
        done()
      .catch done

  describe '::_ensureDefaults', ->

    it 'should add variant defaults to all variants', ->
      sampleVariantWithoutAttr = _.deepClone(sampleVariant1)
      delete sampleVariantWithoutAttr.attributes

      sampleProduct = {}
      sampleProduct.masterVariant = _.deepClone(sampleMasterVariant)
      sampleProduct.variants =  [ _.deepClone(sampleVariantWithoutAttr),_.deepClone(sampleVariant2)]

      expectedProduct = _.deepClone(sampleProduct)
      expectedProduct.masterVariant.prices = []
      expectedProduct.variants[0].prices = []
      expectedProduct.variants[0].attributes = []
      expectedProduct.variants[1].prices = []

      updatedProduct = @import._ensureDefaults(sampleProduct)
      expect(updatedProduct).toEqual expectedProduct

  describe ':: Custom reference resolution', ->

    it ' :: should detect reference type attribute', ->
      sampleReferenceAttribute =
        name: 'foobar'
        value:
          value: 'some value'
          resolvePredicate: 'some predicate query'
          endpoint: 'some endpoint'

      sampleNonReferenceAttribute =
        name: 'some non reference attribute'
        value: 'some value'

      expect(@import._isReferenceTypeAttribute(sampleReferenceAttribute.value)).toBeTruthy()
      expect(@import._isReferenceTypeAttribute(sampleNonReferenceAttribute.value)).toBeFalsy()

    it ' :: should resolve to correct reference value', (done) ->
      sampleReferenceObject =
        value: 'xyz'
        resolvePredicate: 'masterVariant(sku="xyz")'
        endpoint: 'productProjections'

      expectedResult = 'some uuid'

      spyOn(@import, '_resolveReference').andCallFake -> Promise.resolve('some uuid')
      @import._resolveCustomReference(sampleReferenceObject)
      .then (result) ->
        expect(result).toEqual expectedResult
        done()
      .catch (err) ->
        done(err)

    it ' :: should resolve the reference correctly', (done) ->
      sampleReferenceObject =
        value: 'xyz'
        resolvePredicate: 'masterVariant(sku="xyz")'
        endpoint: 'productProjections'

      expectedResponse =
        body:
          results: [
            id: 'some uuid'
          ]

      @import._resetCache()
      spyOn(@import.client.productProjections, "fetch").andCallFake -> Promise.resolve(expectedResponse)
      @import._resolveCustomReference(sampleReferenceObject)
      .then (result) ->
        expect(result).toEqual 'some uuid'
        done()
      .catch (err) ->
        done(err)


    it ' :: should fetch and resolve the custom reference in a variant', (done) ->
      sampleVariantWithResolveableAttr = _.deepClone sampleMasterVariant

      sampleReferenceAttribute =
        name: 'sample reference attribute'
        value:
          value: 'xyz'
          resolvePredicate: 'masterVariant(sku="xyz")'
          endpoint: 'productProjections'

      expectedClientResponse =
        body:
          results: [
            id: 'some uuid'
          ]

      expectedResolvedVariant = _.deepClone sampleMasterVariant

      sampleResolvedReference =
        name: 'sample reference attribute'
        value: 'some uuid'

      expectedResolvedVariant.attributes.push(sampleResolvedReference)
      expectedResolvedVariant.attributes.push(sampleResolvedReference)

      sampleVariantWithResolveableAttr.attributes.push(sampleReferenceAttribute)
      sampleVariantWithResolveableAttr.attributes.push(sampleReferenceAttribute)
      spyOn(@import.client.productProjections, "fetch").andCallFake -> Promise.resolve(expectedClientResponse)
      @import._fetchAndResolveCustomReferencesByVariant(sampleVariantWithResolveableAttr)
      .then (result) ->
        expect(result).toEqual expectedResolvedVariant
        done()
      .catch (err) ->
        done(err)

    it ' :: should resolve custom reference set in a variant', (done) ->
      sampleVariantWithResolveableAttr = _.deepClone sampleMasterVariant

      sampleReferenceAttribute =
        name: 'sample reference attribute'
        value: [
          value: 'xyz'
          resolvePredicate: 'masterVariant(sku="xyz")'
          endpoint: 'productProjections'
        ,
          value: 'xyz'
          resolvePredicate: 'masterVariant(sku="xyz")'
          endpoint: 'productProjections'
        ]

      expectedClientResponse =
        body:
          results: [
            id: 'some uuid'
          ]

      expectedResolvedVariant = _.deepClone sampleMasterVariant

      sampleResolvedReference =
        name: 'sample reference attribute'
        value: ['some uuid','some uuid']

      expectedResolvedVariant.attributes.push(sampleResolvedReference)

      sampleVariantWithResolveableAttr.attributes.push(sampleReferenceAttribute)
      spyOn(@import.client.productProjections, "fetch").andCallFake -> Promise.resolve(expectedClientResponse)
      @import._fetchAndResolveCustomReferencesByVariant(sampleVariantWithResolveableAttr)
      .then (result) ->
        expect(result).toEqual expectedResolvedVariant
        done()
      .catch (err) ->
        done(err)

    it ' :: should not throw error in case of variant with no attributes', (done) ->
      sampleVariantWithoutAttributes =
        sku: '12345'
        id: 1
        images: []

      sampleVariantWithEmptyAttributes =
        sku: '12345'
        id: 1
        attributes: []
        images: []

      @import._fetchAndResolveCustomReferencesByVariant(sampleVariantWithoutAttributes)
      .then (result) ->
        expect(result).toEqual sampleVariantWithoutAttributes
      @import._fetchAndResolveCustomReferencesByVariant(sampleVariantWithEmptyAttributes)
      .then (result) ->
        expect(result).toEqual sampleVariantWithEmptyAttributes
        done()
      .catch (err) ->
        done(err)







