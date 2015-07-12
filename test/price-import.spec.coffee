_ = require 'underscore'
_.mixin require 'underscore-mixins'
{PriceImport} = require '../lib'
Config = require '../config'
Promise = require 'bluebird'

describe 'PriceImport', ->

  beforeEach ->
    @import = new PriceImport null, Config

  it 'should initialize', ->
    expect(@import).toBeDefined()

  describe '::_wrapPricesIntoProducts', ->

    it 'should wrap a product around a single price', ->
      products =
        products: [
          {
          id: 'id123'
          masterVariant:
            sku: '123'
          }
        ]
      prices =
        prices: [
          {
          sku: '123'
          value:
            currencyCode: 'EUR'
            centAmount: 799
          country: 'DE'
          validFrom: '2000-01-01T00:00:00'
          validTo: '2099-12-31T23:59:59'
          }
        ]

      products = @import._wrapPricesIntoProducts prices, products
      console.log "RRRRRRR", products[0].masterVariant.prices
      price = prices.prices[0]
      expect(products[0].masterVariant.sku).toBe price.sku
      expect(_.size products[0].masterVariant.prices).toBe 1
      console.log "SKU", products[0].masterVariant.prices[0].sku
      expect(products[0].masterVariant.prices[0].sku).toBeUndefined()
      expect(products[0].masterVariant.prices[0].value).toEqual price.value
      expect(products[0].masterVariant.prices[0].validFrom).toEqual price.validFrom
      expect(products[0].masterVariant.prices[0].validTo).toEqual price.validTo
      expect(products[0].masterVariant.prices[0].country).toEqual price.country
      # channel
      # customerGroup
