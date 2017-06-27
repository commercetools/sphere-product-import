_ = require 'underscore'
_.mixin require 'underscore-mixins'
{EnsureDefaultAttributes} = require '../lib'
{ExtendedLogger} = require 'sphere-node-utils'
package_json = require '../package.json'

defaultAttributes = [
  name: 'defaultAttribute1'
  value: 'attributeValue1'
,
  name: 'defaultAttribute2'
  value: 'attributeValue2'
,
  name: 'defaultAttribute3'
  value: 'attributeValue3'
,
  name: 'booleanTrueAttribute'
  value: true
,
  name: 'booleanFalseAttribute'
  value: false
]

variantAttributes = [
  name: 'attributeName1'
  value: 'attributeValue1'
,
  name: 'attributeName2'
  value: 'attributeValue2'
,
  name: 'attributeName3'
  value: 'attributeValue3'
,
  name: 'attributeName4'
  value: 'attributeValue4'
]

describe 'Ensure default attributes unit tests', ->

  beforeEach ->
    @logger = new ExtendedLogger
    additionalFields:
      project_key: 'ensureDefaultAttributes'
    logConfig:
      name: "#{package_json.name}-#{package_json.version}"
      streams: [
        { level: 'info', stream: process.stdout }
      ]

    @import = new EnsureDefaultAttributes(@logger, defaultAttributes)

  it ' :: should initialize', ->
    expect(@import).toBeDefined()

  it ' :: should find existing attribute', ->
    extendedVariantAttributes = _.deepClone(variantAttributes)
    extendedVariantAttributes.push(defaultAttributes[0])
    expect(@import._isAttributeExisting(defaultAttributes[0], extendedVariantAttributes)).toBeTruthy()
    expect(@import._isAttributeExisting(defaultAttributes[1],variantAttributes)).toBeFalsy()

  it ' :: should ensure default attributes in variant', ->
    inputVariant = {}
    extendedVariantAttributes = _.deepClone(variantAttributes)
    extendedVariantAttributes.push(defaultAttributes[0])
    inputVariant.attributes = extendedVariantAttributes
    expectedVariant = _.deepClone(inputVariant)
    expectedVariant.attributes.push(defaultAttributes[1])
    expectedVariant.attributes.push(defaultAttributes[2])
    expectedVariant.attributes.push(defaultAttributes[3])
    expectedVariant.attributes.push(defaultAttributes[4])
    expect(@import._ensureInVariant(inputVariant)).toEqual(expectedVariant)

  it ' :: should ensure default attributes in product', (done) ->
    inputVariant = {}
    extendedVariantAttributes = _.deepClone(variantAttributes)
    extendedVariantAttributes.push(defaultAttributes[0])
    inputVariant.attributes = extendedVariantAttributes
    expectedVariant = _.deepClone(inputVariant)
    expectedVariant.attributes.push(defaultAttributes[1])
    expectedVariant.attributes.push(defaultAttributes[2])
    expectedVariant.attributes.push(defaultAttributes[3])
    expectedVariant.attributes.push(defaultAttributes[4])
    inputProduct = {}
    inputProduct.masterVariant = inputVariant
    inputProduct.variants = []
    inputProduct.variants.push(inputVariant)
    expectedProduct = {}
    expectedProduct.masterVariant = expectedVariant
    expectedProduct.variants = []
    expectedProduct.variants.push(expectedVariant)
    @import.ensureDefaultAttributesInProduct(inputProduct)
    .then (updatedProduct) ->
      expect(updatedProduct).toEqual(expectedProduct)
      done()
    .catch done

  it ' :: should not overwrite existing attributes', (done) ->
    inputVariant = {}
    oldDefaultAttributes = _.deepClone(defaultAttributes)
    extendedVariantAttributes = _.deepClone(variantAttributes)
    inputVariant.attributes = extendedVariantAttributes
    inputProduct = {}
    inputProduct.masterVariant = inputVariant
    inputProduct.variants = [inputVariant]

    serverVariant = {}
    expectedAttributeValue = 'attributeValue11'
    serverAttribute =
      name: 'defaultAttribute1'
      value: expectedAttributeValue
    serverAttributes = [serverAttribute]

    serverVariant.attributes = serverAttributes
    serverProduct = {}
    serverProduct.masterVariant = serverVariant
    serverProduct.variants = [serverVariant]

    @import.ensureDefaultAttributesInProduct(inputProduct, serverProduct)
    .then (updatedProduct) =>
      expectedMasterAttribute = @import._isAttributeExisting(serverAttribute, updatedProduct.masterVariant.attributes)
      expect(expectedMasterAttribute.value).toBe(expectedAttributeValue)

      expectedVariantAttribute = @import._isAttributeExisting(serverAttribute, updatedProduct.variants[0].attributes)
      expect(expectedVariantAttribute.value).toBe(expectedAttributeValue)
      expect(defaultAttributes).toEqual(oldDefaultAttributes)
    .finally done