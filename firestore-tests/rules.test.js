// Security rules tests for firestore.rules, run against the Firestore emulator.
// `npm test` starts the emulator, runs these with `node --test`, then stops it.
import { after, before, beforeEach, describe, test } from "node:test";
import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, getDocs, collection, setDoc, Timestamp } from "firebase/firestore";

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-smart-grocery",
    firestore: { rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8") },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

const alice = () => env.authenticatedContext("alice").firestore();
const bob = () => env.authenticatedContext("bob").firestore();
const signedOut = () => env.unauthenticatedContext().firestore();

/// The fields GroceryItem encodes (pinned in ModelKeysTests.swift).
const item = (overrides = {}) => ({
  id: "item-1",
  title: "Milk",
  notes: "",
  aisle: "Dairy",
  isCompleted: false,
  createdAt: Timestamp.now(),
  updatedAt: Timestamp.now(),
  ...overrides,
});

/// Writes seed data as an admin, bypassing the rules.
const seed = (path, data) =>
  env.withSecurityRulesDisabled((context) => setDoc(doc(context.firestore(), path), data));

describe("owner", () => {
  test("can write and read their items", async () => {
    await assertSucceeds(setDoc(doc(alice(), "users/alice/items/item-1"), item()));
    await assertSucceeds(getDoc(doc(alice(), "users/alice/items/item-1")));
    await assertSucceeds(getDocs(collection(alice(), "users/alice/items")));
  });

  test("can delete their items", async () => {
    await seed("users/alice/items/item-1", item());
    await assertSucceeds(deleteDoc(doc(alice(), "users/alice/items/item-1")));
  });

  test("can write and read their preferences", async () => {
    await assertSucceeds(setDoc(doc(alice(), "users/alice/preferences/main"), { homeArrivalDelay: 600 }));
    await assertSucceeds(getDoc(doc(alice(), "users/alice/preferences/main")));
  });

  test("can write and read their user document", async () => {
    await assertSucceeds(setDoc(doc(alice(), "users/alice"), { createdAt: Timestamp.now() }));
    await assertSucceeds(getDoc(doc(alice(), "users/alice")));
  });
});

describe("another user", () => {
  beforeEach(async () => {
    await seed("users/alice/items/item-1", item());
    await seed("users/alice/preferences/main", { homeArrivalDelay: 600 });
  });

  test("can't read someone else's items or preferences", async () => {
    await assertFails(getDoc(doc(bob(), "users/alice/items/item-1")));
    await assertFails(getDocs(collection(bob(), "users/alice/items")));
    await assertFails(getDoc(doc(bob(), "users/alice/preferences/main")));
  });

  test("can't write or delete someone else's data", async () => {
    await assertFails(setDoc(doc(bob(), "users/alice/items/item-2"), item({ id: "item-2" })));
    await assertFails(setDoc(doc(bob(), "users/alice/preferences/main"), { homeArrivalDelay: 5 }));
    await assertFails(deleteDoc(doc(bob(), "users/alice/items/item-1")));
  });
});

describe("signed out", () => {
  test("can't read or write anything", async () => {
    await seed("users/alice/items/item-1", item());
    await assertFails(getDoc(doc(signedOut(), "users/alice/items/item-1")));
    await assertFails(setDoc(doc(signedOut(), "users/alice/items/item-2"), item({ id: "item-2" })));
  });
});

describe("outside the known paths", () => {
  test("other collections are denied even when signed in", async () => {
    await assertFails(setDoc(doc(alice(), "lists/anything"), { title: "x" }));
    await assertFails(getDoc(doc(alice(), "lists/anything")));
    await assertFails(getDoc(doc(alice(), "alice/items")));
  });

  test("unknown subcollections of the user's own tree are denied", async () => {
    await assertFails(setDoc(doc(alice(), "users/alice/secrets/one"), { x: 1 }));
  });
});

describe("item validation", () => {
  test("rejects unknown fields", async () => {
    await assertFails(setDoc(doc(alice(), "users/alice/items/item-1"), item({ price: 3 })));
  });

  test("rejects a missing or empty title", async () => {
    const { title, ...noTitle } = item();
    await assertFails(setDoc(doc(alice(), "users/alice/items/item-1"), noTitle));
    await assertFails(setDoc(doc(alice(), "users/alice/items/item-1"), item({ title: "" })));
  });

  test("rejects wrong types and oversized text", async () => {
    await assertFails(setDoc(doc(alice(), "users/alice/items/item-1"), item({ isCompleted: "yes" })));
    await assertFails(setDoc(doc(alice(), "users/alice/items/item-1"), item({ title: "x".repeat(501) })));
  });

  test("rejects missing or non-timestamp dates", async () => {
    const { createdAt, ...noCreatedAt } = item();
    await assertFails(setDoc(doc(alice(), "users/alice/items/item-1"), noCreatedAt));
    await assertFails(setDoc(doc(alice(), "users/alice/items/item-1"), item({ updatedAt: "yesterday" })));
  });

  test("rejects an id that doesn't match the document", async () => {
    await assertFails(setDoc(doc(alice(), "users/alice/items/item-1"), item({ id: "item-2" })));
  });
});
