# Agent Instructions

## Completion Notes

When finishing a user-facing change, always include a concrete in-app test flow in the final response.

The flow should be written for a person using the app, not only for command-line verification. Include:

1. the starting state or setup needed
2. the exact screens/buttons/actions to use
3. the expected result after each important step
4. any offline/backend-failure behavior that matters for the change
5. any known verification gap, if the app flow could not be run locally

Still include build/test commands when relevant, but do not treat them as a substitute for the manual app flow.
