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
      products = [
        {
          id: 'id123'
          masterVariant:
            sku: '123'
        }
      ]
      prices = [
        {
          sku: '123'
          prices: [
            {
              value:
                currencyCode: 'EUR'
                centAmount: 799
              country: 'DE'
              validFrom: '2000-01-01T00:00:00'
              validTo: '2099-12-31T23:59:59'
            }
          ]
        }
      ]

      modifiedProducts = @import._wrapPricesIntoProducts prices, products
      expect(_.size modifiedProducts).toBe 1
      product = modifiedProducts[0]
      price = prices[0].prices[0]
      expect(product.masterVariant.sku).toBe prices[0].sku
      expect(_.size product.masterVariant.prices).toBe 1
      expect(product.masterVariant.prices[0].sku).toBeUndefined()
      expect(product.masterVariant.prices[0].value).toEqual price.value
      expect(product.masterVariant.prices[0].validFrom).toEqual price.validFrom
      expect(product.masterVariant.prices[0].validTo).toEqual price.validTo
      expect(product.masterVariant.prices[0].country).toEqual price.country
      # channel
      # customerGroup

    it 'should add all prices to the product', ->
      products = [
        {
          id: 'id123'
          masterVariant:
            sku: '123'
        }
      ]
      prices = [
        {
          sku: '123'
          prices: [
            {
              value:
                currencyCode: 'EUR'
                centAmount: 799
              country: 'DE'
              validFrom: '2000-01-01T00:00:00'
              validTo: '2099-12-31T23:59:59'
            }
            {
              value:
                currencyCode: 'USD'
                centAmount: 1099
              country: 'US'
              validFrom: '2000-01-01T00:00:00'
              validTo: '2099-12-31T23:59:59'
            }
          ]
        }
      ]

      modifiedProducts = @import._wrapPricesIntoProducts prices, products
      expect(_.size modifiedProducts).toBe 1
      expect(_.size modifiedProducts[0].masterVariant.prices).toBe 2
