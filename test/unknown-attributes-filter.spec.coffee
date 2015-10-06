debug = require('debug')('spec:unknown-attributes-filter')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
{UnknownAttributesFilter} = require '../lib'
Promise = require 'bluebird'
{ExtendedLogger} = require 'sphere-node-utils'
package_json = require '../package.json'

sampleAttributeNameList = [
  'attributeName1'
,
  'attributeName2'
,
  'attributeName3'
]

sampleAttributeList = [
  name: 'attributeName4'
  value: 'attributeValue'
,
  name: 'attributeName1'
  value: 'attributeValue'
,
  name: 'attributeName5'
  value: 'attributeValue'
,
  name: 'attributeName3'
  value: 'attributeValue'
]

expectedAttributeList = [
  name: 'attributeName1'
  value: 'attributeValue'
,
  name: 'attributeName3'
  value: 'attributeValue'
]

describe 'Unknown Attributes Filter unit tests', ->

  beforeEach ->
    @logger = new ExtendedLogger
      additionalFields:
        project_key: 'unknownAttributesFilter'
      logConfig:
        name: "#{package_json.name}-#{package_json.version}"
        streams: [
          { level: 'info', stream: process.stdout }
        ]

    @import = new UnknownAttributesFilter @logger

  it ' :: should initialize', ->
    expect(@import).toBeDefined()

  it ' :: should filter known attributes', (done) ->

    @import._filterAttributes(sampleAttributeNameList,sampleAttributeList)
    .then (result) ->
      expect(result).toEqual expectedAttributeList
      done()
    .catch (err) ->
      done(err)

  it ' :: should filter attributes correctly from a variant', (done) ->
    sampleVariant =
      attributes: _.deepClone sampleAttributeList

    expectedVariant =
      attributes: _.deepClone expectedAttributeList

    @import._filterVariantAttributes(sampleVariant, sampleAttributeNameList)
    .then (variant) ->
      expect(variant).toEqual expectedVariant
      done()
    .catch (err) ->
      done(err)

  it ' :: should filter attributes of all variants of a product correctly', (done) ->

    sampleVariant =
      attributes: _.deepClone sampleAttributeList

    sampleProduct =
      masterVariant:
        sku: 'masterVariant'
        attributes: _.deepClone sampleAttributeList
      variants: [
        _.deepClone sampleVariant
      ,
        _.deepClone sampleVariant
      ,
        _.deepClone sampleVariant
      ]

    sampleExpectedVariant =
      attributes: _.deepClone expectedAttributeList

    sampleExpectedProduct =
      masterVariant:
        sku: 'masterVariant'
        attributes: _.deepClone expectedAttributeList
      variants: [
        _.deepClone sampleExpectedVariant
      ,
        _.deepClone sampleExpectedVariant
      ,
        _.deepClone sampleExpectedVariant
      ]

    productType =
      attributes: [
        name: 'attributeName1'
        value: 'attributeValue'
      ,
        name: 'attributeName2'
        value: 'attributeValue'
      ,
        name: 'attributeName3'
        value: 'attributeValue'
      ]

    @import.filter(productType,sampleProduct)
    .then (product) ->
      expect(product).toEqual sampleExpectedProduct
      done()
    .catch (err) ->
      done(err)

  it ' :: should resolve empty when product type has no attributes', (done) ->
    sampleVariant =
      attributes: _.deepClone sampleAttributeList

    sampleProduct =
      masterVariant:
        attributes: _.deepClone sampleAttributeList
      variants: [
        _.deepClone sampleVariant
      ,
        _.deepClone sampleVariant
      ,
        _.deepClone sampleVariant
      ]

    productType = {}

    @import.filter(productType, sampleProduct)
    .then (result) ->
      expect(result).toBeUndefined()
      done()
    .catch (err) ->
      done(err)