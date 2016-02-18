# Sphere Product Discounts Importer 
Product Discounts Importer is used to create or update discounts for existing products in a project.

### Configuration
 The constructor requires the following:
  * logger instance
  * sphere client (sphere-node-sdk) configuration
    * project credentials
    * user-agent

#### Default configuration
 * The dafult language is set to `en`.
 
### Sample Input
    {
      "discounts": [
        {
          "name": {
            "en": "30 percent off"
          },
          "value": {
            "type": "relative",
            "permyriad": 3000
          },
          "predicate": "attributes.product_id in (\"product_id_1\", \"product_id_2\", \"product_id_3\", \"product_id_4\")",
          "sortOrder": "0.3"
        },
        {
          "name": {
            "en": "35 percent off"
          },
          "value": {
            "type": "relative",
            "permyriad": 3500
          },
          "predicate": "attributes.product_id in (\"product_id_5\", \"product_id_6\", \"product_id_7\", \"product_id_8\")",
          "sortOrder": "0.35"
        }
      ]
    }

 * `predicate` can be replaced with any valid query that fetches the products in belonging to the discount.

### Caveat
 * Currently it checks for existing discounts by `name.en` only. This will be updated when there is an `external id` available for the product discounts in the API. 
 * The language is set default to `en`. Will be made configurable later with future iterations.
 
