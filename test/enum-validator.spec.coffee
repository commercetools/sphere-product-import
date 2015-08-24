debug = require('debug')('spec:enum-validator')
_ = require 'underscore'
_.mixin require 'underscore-mixins'
{EnumValidator} = require '../lib'
Promise = require 'bluebird'
slugify = require 'underscore.string/slugify'
{ExtendedLogger} = require 'sphere-node-utils'
package_json = require '../package.json'

sampleVariant =
  sku: 'sample_sku'
  attributes: [

  ]

sampleProductType =
  id: 'sample_product_type_id'
  version: 1
  name: 'sample product type name'
  attributes: [
    name: 'sample-localized-text--attribute'
    label:
      en: 'Sample Localized Text Attribute'
    isRequired: true
    type:
      name: 'text'
  ,
    name: 'sample-lenum-attribute'
    label:
      en: 'Sample Lenum Attribute'
    type:
      name: 'lenum'
      values: [
        key: 'lenum-key-1'
        label:
          en: 'lenum-1-label-en'
          de: 'lenum-1-label-de'
      ,
        key: 'lenum-key-2'
        label:
          en: 'lenum-2-label-en'
          de: 'lenum-2-label-de'
      ]
  ,
    name: 'sample-enum-attribute'
    label:
      en: 'Sample Enum Attribute'
    type:
      name: 'enum'
      values: [
        key: 'enum-1-key'
        label: 'enum-1-label'
      ,
        key: 'enum-2-key'
        label: 'enum-2-label'
      ]
  ,
    name: 'sample-set-enum-attribute'
    label:
      en: 'Sample Set Enum Attribute'
    type:
      name: 'set'
      elementType:
        name: 'enum'
        values: [
          key: 'enum-set-1-key'
          label: 'enum-set-1-label'
        ,
          key: 'enum-set-2-key'
          label: 'enum-set-2-label'
        ]
  ,
    name: 'sample-set-lenum-attribute'
    label:
      en: 'Sample Set Lenum Attribute'
    type:
      name: 'set'
      elementType:
        name: 'lenum'
        values: [
          key: 'lenum-set-1-key'
          label:
            en: 'lenum-set-1-label-en'
            de: 'lenum-set-1-label-de'
        ,
          key: 'lenum-set-2-key'
          label:
            en: 'lenum-set-2-label-en'
            de: 'lenum-set-2-label-de'
        ]
  ]


describe 'Enum Validator unit tests', ->

  beforeEach ->
    @logger = new ExtendedLogger
      additionalFields:
        project_key: 'enumValidator'
      logConfig:
        name: "#{package_json.name}-#{package_json.version}"
        streams: [
          { level: 'info', stream: process.stdout }
        ]

    @import = new EnumValidator @logger, null

  it ' :: should initialize', ->
    expect(@import).toBeDefined()

  it ' :: should filter enum and lenum attributes', ->
    enums = _.filter(sampleProductType.attributes, @import._enumLenumFilterPredicate)
    expect(_.size enums).toBe 2

  it ' :: should filter set of enum attributes', ->
    enums = _.filter(sampleProductType.attributes, @import._enumSetFilterPredicate)
    expect(_.size enums).toBe 1

  it ' :: should filter set of lenum attributes', ->
    enums = _.filter(sampleProductType.attributes, @import._lenumSetFilterPredicate)
    expect(_.size enums).toBe 1

  it ' :: should extract enum attributes from product type', ->
    enums = @import._extractEnumAttributesFromProductType(sampleProductType)
    expect(_.size enums).toBe 4

  it ' :: should fetch enum attributes from sample product type', ->
    enums = @import._fetchEnumAttributesOfProductType(sampleProductType)
    expect(_.size enums).toBe 4

  it ' :: should fetch enum attributes of sample product type from cache', ->
    spyOn(@import, '_extractEnumAttributesFromProductType').andCallThrough()
    @import._fetchEnumAttributesOfProductType(sampleProductType)
    enums = @import._fetchEnumAttributesOfProductType(sampleProductType)
    expect(_.size enums).toBe 4
    expect(@import._extractEnumAttributesFromProductType.calls.length).toEqual 1
    expect(@import._cache.productTypeEnumMap[sampleProductType.id]).toBeDefined()

  it ' :: should fetch enum attribute names of sample product type', ->
    expectedNames = ['sample-lenum-attribute', 'sample-enum-attribute', 'sample-set-enum-attribute', 'sample-set-lenum-attribute']
    enumNames = @import._fetchEnumAttributeNamesOfProductType(sampleProductType)
    expect(enumNames).toEqual expectedNames

  it ' :: should fetch enum attribute names of sample product type from cache', ->
    spyOn(@import, '_fetchEnumAttributesOfProductType').andCallThrough()
    @import._fetchEnumAttributeNamesOfProductType(sampleProductType)
    enumNames = @import._fetchEnumAttributeNamesOfProductType(sampleProductType)
    expect(_.size enumNames).toBe 4
    expect(@import._fetchEnumAttributesOfProductType.calls.length).toEqual 1
    expect(@import._cache.productTypeEnumMap["#{sampleProductType.id}_names"]).toBeDefined()