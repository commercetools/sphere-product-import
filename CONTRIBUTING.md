# Contributing

## Important notes
Please don't edit files in the `lib` subdirectory as they are generated via Grunt. You'll find source code in the `src` subdirectory!

### Code style
Regarding code style like indentation and whitespace, **follow the conventions you see used in the source already.**

## Modifying the code
First, ensure that you have the latest [Node.js](http://nodejs.org/) and [npm](http://npmjs.org/) installed.

1. Fork and clone the repo.
1. Run `npm install` to install all dependencies (including Grunt).
1. Run `npm test` to build the JavaScript code and test it.

Assuming that you don't see any red, you're ready to go. Just be sure to run `npm test` after making any changes, to ensure that nothing is broken. You can also use grunt to do this automatically for you: `npm run watchChanges`

## Submitting pull requests

1. Create a new branch, please don't work in your `master` branch directly.
1. Add failing tests for the change you want to make. Run `npm test` to see the tests fail.
1. Fix stuff.
1. Run `npm test` to see if the tests pass. Repeat steps 2-4 until done.
1. Update the documentation to reflect any changes.
1. Push to your fork and submit a pull request.

## Styleguide
We <3 CoffeeScript! So please have a look at this referenced [coffeescript styleguide](https://github.com/polarmobile/coffeescript-style-guide) when doing changes to the code.
