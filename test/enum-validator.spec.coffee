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
    name: 'sample-localized-text-attribute'
    value:
      en: 'sample localized text value'
  ,
    name: 'sample-lenum-attribute'
    value: 'lenum-key-2'
  ,
    name: 'sample-enum-attribute'
    value: 'enum-1-key'
  ,
    name: 'sample-set-enum-attribute'
    value: 'enum-set-2-key'
  ]

sampleProductType =
  id: 'sample_product_type_id'
  version: 1
  name: 'sample product type name'
  attributes: [
    name: 'sample-localized-text-attribute'
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

  it ' :: should detect enum attribute', ->
    sampleEnumAttribute =
      name: 'sample-enum-attribute'
    sampleAttribute =
      name: 'sample-text-attribute'
    enumAttributeNames = ['sample-lenum-attribute', 'sample-enum-attribute', 'sample-set-enum-attribute', 'sample-set-lenum-attribute']
    expect(@import._isEnumVariantAttribute(sampleEnumAttribute, enumAttributeNames)).toBeTruthy()
    expect(@import._isEnumVariantAttribute(sampleAttribute, enumAttributeNames)).toBeFalsy()

  it ' :: should fetch enum attributes from sample variant', ->
    enums = @import._fetchEnumAttributesFromVariant(sampleVariant,sampleProductType)
    expect(_.size enums).toBe 3

  it ' :: should fetch all enum attributes from all product variants', ->
    sampleProduct =
      name: 'sample Product'
      productType:
        id: 'sample_product_type_id'
      masterVariant: _.deepClone sampleVariant
      variants: [
        _.deepClone sampleVariant
      ,
        _.deepClone sampleVariant
      ]

    enums = @import._fetchEnumAttributesFromProduct(sampleProduct, sampleProductType)
    expect(_.size enums).toBe 9

  it ' :: should detect enum key correctly', ->
    enumAttributeTrue =
      name: 'sample-enum-attribute'
      value: 'enum-2-key'

    enumAttributeFalse =
      name: 'sample-enum-attribute'
      value: 'enum-3-key'

    lenumAttributeTrue =
      name: 'sample-lenum-attribute'
      value: 'lenum-key-2'

    lenumAttributeFalse =
      name: 'sample-lenum-attribute'
      value: 'lenum-key-3'

    lenumSetAttributeTrue =
      name: 'sample-set-lenum-attribute'
      value: 'lenum-set-1-key'

    lenumSetAttributeFalse =
      name: 'sample-set-lenum-attribute'
      value: 'lenum-set-5-key'

    enumSetAttributeTrue =
      name: 'sample-set-enum-attribute'
      value: 'enum-set-1-key'

    enumSetAttributeFalse =
      name: 'sample-set-enum-attribute'
      value: 'enum-set-5-key'

    expect(@import._isEnumKeyPresent(enumAttributeTrue, sampleProductType.attributes[2])).toBeDefined()
    expect(@import._isEnumKeyPresent(enumAttributeFalse, sampleProductType.attributes[2])).toBeUndefined()
    expect(@import._isEnumKeyPresent(lenumAttributeTrue, sampleProductType.attributes[1])).toBeDefined()
    expect(@import._isEnumKeyPresent(lenumAttributeFalse, sampleProductType.attributes[1])).toBeUndefined()
    expect(@import._isEnumKeyPresent(lenumSetAttributeTrue, sampleProductType.attributes[4])).toBeDefined()
    expect(@import._isEnumKeyPresent(lenumSetAttributeFalse, sampleProductType.attributes[4])).toBeUndefined()
    expect(@import._isEnumKeyPresent(enumSetAttributeTrue, sampleProductType.attributes[3])).toBeDefined()
    expect(@import._isEnumKeyPresent(enumSetAttributeFalse, sampleProductType.attributes[3])).toBeUndefined()

  it ' :: should generate correct enum update action', ->
    enumAttribute =
      name: 'sample-enum-attribute'
      value: 'enum-3-key'

    expectedUpdateAction =
      action: 'addPlainEnumValue'
      attributeName: 'sample-enum-attribute'
      value:
        key: 'enum-3-key'
        label: 'enum-3-key'

    expect(@import._generateUpdateAction(enumAttribute, sampleProductType.attributes[2])).toEqual expectedUpdateAction

  it ' :: should generate correct lenum update action', ->
    lenumAttribute =
      name: 'sample-lenum-attribute'
      value: 'lenum-3-key'

    expectedUpdateAction =
      action: 'addLocalizedEnumValue'
      attributeName: 'sample-lenum-attribute'
      value:
        key: 'lenum-3-key'
        label:
          en: 'lenum-3-key'
          de: 'lenum-3-key'
          fr: 'lenum-3-key'
          it: 'lenum-3-key'
          es: 'lenum-3-key'

    expect(@import._generateUpdateAction(lenumAttribute, sampleProductType.attributes[1])).toEqual expectedUpdateAction

  it ' :: should generate correct enum set update action', ->
    enumSetAttribute =
      name: 'sample-set-enum-attribute'
      value: 'enum-set-5-key'

    expectedUpdateAction =
      action: 'addPlainEnumValue'
      attributeName: 'sample-set-enum-attribute'
      value:
        key: 'enum-set-5-key'
        label: 'enum-set-5-key'

    expect(@import._generateUpdateAction(enumSetAttribute, sampleProductType.attributes[3])).toEqual expectedUpdateAction

  it ' :: should generate correct list of update actions', (done) ->
    enumAttributes = [
      name: 'sample-lenum-attribute'
      value: 'lenum-key-2'
    ,
      name: 'sample-enum-attribute'
      value: 'enum-1-key'
    ,
      name: 'sample-set-enum-attribute'
      value: 'enum-set-2-key'
    ,
      name: 'sample-lenum-attribute'
      value: 'lenum-3-key'
    ,
      name: 'sample-enum-attribute'
      value: 'enum-3-key'
    ,
      name: 'sample-set-enum-attribute'
      value: 'enum-set-5-key'
    ]

    expectedUpdateActions = [
      action: 'addLocalizedEnumValue'
      attributeName: 'sample-lenum-attribute'
      value:
        key: 'lenum-3-key'
        label:
          en: 'lenum-3-key'
          de: 'lenum-3-key'
          fr: 'lenum-3-key'
          it: 'lenum-3-key'
          es: 'lenum-3-key'
    ,
      action: 'addPlainEnumValue'
      attributeName: 'sample-enum-attribute'
      value:
        key: 'enum-3-key'
        label: 'enum-3-key'
    ,
      action: 'addPlainEnumValue'
      attributeName: 'sample-set-enum-attribute'
      value:
        key: 'enum-set-5-key'
        label: 'enum-set-5-key'
    ]

    @import._validateEnums(enumAttributes, sampleProductType)
    .then (updateActions) ->
      expect(updateActions).toEqual expectedUpdateActions
      done()
    .catch (err) ->
      done(err)
