# Sphere Product Importer
Accepts a list of products in a valid [JSON Schema](https://github.com/sphereio/sphere-json-schemas/tree/master/schema). Processes them in batches (of default: 30 products).
 Assumes the following to be existing in the concerned project:
 * `Product Types` with correct names used by the products to be imported
  * All the attributes should be existing with the correct types
  * All the enums should be existing with the correct keys
 * All the `categories` with the correct external ids used by the data to be imported
 * All `tax categories` be existing with the correct names to be used by the date to be imported

### Configuration
 The constructor requires the following:
  * logger instance
  * configuration object
    * sphere client (sphere-node-sdk) configuration
      * project credentials
      * user-agent
    * errorDir: error directory path (absolute), default: `../errors`
    * errorLimit: maximum number of errors to log, default: 30. If set to 0, logs all errors
    * blackList: array of action groups of Product Sync which are to be black listed. This is to ignore all the update actions generated for the specified action groups. Possible Values:
      * images
      * references
      * prices
      * attributes
      * variants
      * categories
    * ensureEnums: when set to `true`, any new enum keys will be added to existing enums. Default: `false`
    * failOnDuplicateAttr: when set to `true` import will fail when importing product with duplicate attributes, otherwise will take only the first occurrence and log a warning message. Default: `false` 
    * logOnDuplicateAttr: when set to `true` import will log out duplicate attribute message. Default: `true` 
    * filterUnknownAttributes: when set to `true` will ignore any attributes not defined in the product type of the product being imported. Default: `false`
    * ignoreSlugUpdates: when set to `true` will ignore all slug updates for existing product updates. Default: `false`
    * batchSize: number of products to be processed in each batch. Default: 30
    * errorCallback: when set to a custom function, all log messages will be sent to this function. Otherwise, a default logger function will be used
    * defaultAttributes: a list of attributes to be added to all variants if not existing
    * filterActions: can be one of the following:
      * a _function_ that gets called for each action, that the product sync returns. See [here](https://github.com/sphereio/sphere-node-sdk/blob/master/src/coffee/sync/base-sync.coffee#L96) for an example filter. It get's passed the following arguments:
        * the action that should be performed
        * the product that should be updated
        * the product that is being imported
      * an _array_ of update actions that should be ignored

#### Sample configuration object for cli:

    {
      "clientConfig": "sphere-client-credentials-json",
      "errorDir": "../errors",
      "errorLimit": 30,
      "ensureEnums": "true",
      "filterUnknownAttributes": "true",
      "ignoreSlugUpdates": "true",
      "batchSize": 20,
      "blackList": [ "images", "categories" ],
      "defaultAttributes": [
        {"name": "attributeName", "value": "defaultValue"},
        {"name": "attributeName", "value": "defaultValue"}
      ],
      "errorCallback": function(err, logger) {
        logger.error("Error:", err.reason().message)
      }
    }

### Sample Inputs

#### Product Type Reference

      "productType": {
        "id": "product_type_name"
      }

  the `id` is resolved by productType.name

#### Tax Category reference

      "taxCategory": {
        "id": "tax_category_name"
      }

  the `id` is resolved by taxCategory.name

#### Product Category reference

      "categories" : [
        "id" : "category_external_id_1",
        "id" : "category_external_id_2"
      ]

#### Custom Reference Attribute

      {
          "name": "attribute_name",
          "value": "attribute_value_to_resolve_by",
          "type": {
            "name": "reference",
            "referenceTypeId": "resolution-endpoint"
          },
          "_custom": {
            "predicate": custom-predicate-to-use-for-resolution
          }
        }

  referenceTypeId -> suggests the endpoint or entity the reference is to be resolved into, eg: `product`
  predicate -> the custom query to be used to fetch the entity, eg: in case of product ->
    `"masterVariant(sku=\"attribute_value_to_resolve_by\") or variants(sku=\"attribute_value_to_resolve_by\")"`

#### Enum Values
The enum attributes of a product variant are fetched using the product type definition by the attribute name. If the enum attribute value does not exist as a key of the referenced enum attribute, the product type is updated with the new enum key.
* In case of enum:
  * key -> slugified attribute value
  * label -> attribute value
* In case of lenum:
  * key -> slugified attribute value
  * label ->
    * en -> attribute value
    * de -> attribute value
    * fr -> attribute value
    * it -> attribute value
    * es -> attribute value

It handles Enums, Lenums (localized enums), Set of Enums, Set of Lenums.

Acceptable Enum / Lenum / Set < Enum / Lenum > Attribute Samples:

      {
        "name": "enum attribute name",
        "value": "enum key"
      }

Multiple attribute values for a Set < Enum / Lenum > may be specified as individual attributes or also as an array of values:

      {
        "name": "enum1 attribute name",
        "value": "enum1 key 1"
      },
      {
        "name": "enum1 attribute name",
        "value": "enum1 key 2"
      },

      {
        "name": "enum2 attribute name",
        "value": [
          "enum2 key 1",
          "enum2 key 2",
          "enum2 key 3"
        ]
      }

#### Attribute of Type *Set*
```javascript
{
  "name": "sample_set_text",
  "value": ["set_text_1"]
},
{
  "name": "sample_set_text_2",
  "value": ["text_1", "text_2", "text_3"]
}
```
Attributes of type set should have their values as an array even if there is only a single value.

#### Sample Products
 A sample JSON which the importer accepts can be found [here](https://github.com/sphereio/sphere-product-import/blob/master/samples/sample-products.json).
All components of Products in the JSON should be in compliance with the [SPHERE.IO API docs](http://dev.sphere.io/http-api-projects-products.html).
Please refer to the official [SPHERE.IO API docs](http://dev.sphere.io/http-api-projects-products.html) for missing samples in the JSON sample provided above.

### Processing steps
 * Fetches all the existing products by `sku` of their master variant or variants using `productProjections` end point
 * Checks if the product needs to be updated or created new
    * Prepares the product for update if it is an existing product
      * resolves all the `product categories` by `external id` to their internal ids
      * resolves `tax category` for the product by `name` to their internal ids
      * fetches and resolves any or all `custom references` in the product variant attributes according to the reference resolution given in the json block
      * if the update product does not have a `slug` specified, it is assigned the slug of existing product
    * The prepared product is then passed to the sync module to build update actions

    * Prepares the product for creation if it is a new product
      * resolves the `product type` by `name` to its internal id
      * resolves all the `product categories` by `external id` to their internal ids
      * resolves `tax category` for the product by `name` to their internal ids
      * fetches and resolves any or all `custom references` in the product variant attributes according to the reference resolution given in the json block
      * if the slug is missing, it is generated using the product name and timestamp
    * The prepared product is then passed to the `products.create` endpoint.


### Error Handling
By default the importer will continue on errors.
The errors are logged in the logger till the error count reaches the `errorLimit`
The detailed errors from the `sphere-node-sdk` are written to a separate file in the `errorDir`

### Caveats
The known work-arounds. These will be resolved with the release of dependant module updates.
 * Reference resolution: if the resolution by id / name / external-id returns more than one result, then the first one from the list is used
