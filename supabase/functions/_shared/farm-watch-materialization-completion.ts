export type FarmWatchCompletionIdentity = {
  sourceSignature?: unknown;
  externalSourceObservations?: unknown[];
};

export async function recheckFarmWatchMaterializationIdentity<
  T extends FarmWatchCompletionIdentity,
>(args: {
  productKind: string;
  expectedSourceSignature: string;
  resolveCurrent: () => Promise<T>;
}) {
  const expected = String(args.expectedSourceSignature || "");
  if (!expected) {
    throw new Error(args.productKind + " build source identity is missing");
  }

  const current = await args.resolveCurrent();
  const actual = String(current?.sourceSignature || "");
  if (!actual || actual !== expected) {
    throw new Error(
      args.productKind +
        " dependency identity changed during materialization build",
    );
  }
  return current;
}
