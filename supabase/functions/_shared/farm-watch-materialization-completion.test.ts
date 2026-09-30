import { recheckFarmWatchMaterializationIdentity } from "./farm-watch-materialization-completion.ts";

Deno.test("completion identity recheck returns the current matching identity", async () => {
  const observations = [{
    key: "external:test",
    identity_sha256: "a".repeat(64),
  }];
  const result = await recheckFarmWatchMaterializationIdentity({
    productKind: "test-product",
    expectedSourceSignature: "source-v1",
    resolveCurrent: async () => ({
      sourceSignature: "source-v1",
      externalSourceObservations: observations,
    }),
  });
  if (result.externalSourceObservations !== observations) {
    throw new Error(
      "completion identity recheck did not return latest observations",
    );
  }
});

Deno.test("completion identity recheck rejects upstream drift", async () => {
  let rejected = false;
  try {
    await recheckFarmWatchMaterializationIdentity({
      productKind: "test-product",
      expectedSourceSignature: "source-v1",
      resolveCurrent: async () => ({ sourceSignature: "source-v2" }),
    });
  } catch (error) {
    rejected = String(error).includes("dependency identity changed");
  }
  if (!rejected) throw new Error("changed upstream identity was accepted");
});

Deno.test("completion identity recheck rejects unavailable or empty identities", async () => {
  for (
    const current of [{}, { sourceSignature: "" }, { sourceSignature: null }]
  ) {
    let rejected = false;
    try {
      await recheckFarmWatchMaterializationIdentity({
        productKind: "test-product",
        expectedSourceSignature: "source-v1",
        resolveCurrent: async () => current,
      });
    } catch (error) {
      rejected = String(error).includes("dependency identity changed");
    }
    if (!rejected) {
      throw new Error("unavailable upstream identity was accepted");
    }
  }
});
