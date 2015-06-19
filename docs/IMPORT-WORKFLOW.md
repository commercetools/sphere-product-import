# Import workflow

```
+---+
|CSV+-+
+---+ |  +----+   +--------+     +-------+
      +->+JSON+-->+IMPORTER+---->+process|
+---+ |  +----+   +-------++     |Product|
|XML+-+                   |      +---+---+
+---+                     v          ^
                        +-+-----+    |
                        |process+----+
                        |P. Type|
                        +-------+
```

This component expects a JSON input with product data

## Optionally ensure `product-type` for `enums`

Often the product data needs to be updated with new `enum` values, regardless if those values are already existing in the `attribute` definition or not.

If this is not the case, the data cannot be saved.

To ensure that those values are present when importing product data, there should be an automatic process that handles this.

The workflow for that should be as following:

- custom data transformers will prepare the `json` data
- the importer will read the `json` file and build a `product-type` out of it
- the `node-sdk` will create the needed update actions by comparing the assembled `product-type` and the existing one
- the product data will then be imported
