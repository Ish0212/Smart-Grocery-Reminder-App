// Shared lists and invites (Phase 6), run against the Firestore emulator.
import { after, before, beforeEach, describe, test } from "node:test";
import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import {
  arrayRemove,
  arrayUnion,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
} from "firebase/firestore";

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

const as = (uid) => env.authenticatedContext(uid).firestore();
const signedOut = () => env.unauthenticatedContext().firestore();

const seed = (path, data) =>
  env.withSecurityRulesDisabled((context) => setDoc(doc(context.firestore(), path), data));

const item = (overrides = {}) => ({
  id: "item-1",
  title: "Milk",
  notes: "",
  aisle: "",
  isCompleted: false,
  createdAt: Timestamp.now(),
  updatedAt: Timestamp.now(),
  ...overrides,
});

const inDays = (days) => Timestamp.fromMillis(Date.now() + days * 24 * 60 * 60 * 1000);

/// alice owns a list shared with bob; carol is an outsider.
async function seedSharedList() {
  await seed("lists/alice", { ownerId: "alice", memberIds: ["alice", "bob"] });
  await seed("lists/alice/items/item-1", item());
}

describe("creating a list", () => {
  test("you can create your own list", async () => {
    await assertSucceeds(setDoc(doc(as("alice"), "lists/alice"), { ownerId: "alice", memberIds: ["alice"] }));
  });

  test("you can't create someone else's list or add members at creation", async () => {
    await assertFails(setDoc(doc(as("alice"), "lists/bob"), { ownerId: "bob", memberIds: ["bob"] }));
    await assertFails(setDoc(doc(as("alice"), "lists/alice"), { ownerId: "alice", memberIds: ["alice", "carol"] }));
    await assertFails(setDoc(doc(signedOut(), "lists/alice"), { ownerId: "alice", memberIds: ["alice"] }));
  });

  test("lists can't be deleted", async () => {
    await seedSharedList();
    await assertFails(deleteDoc(doc(as("alice"), "lists/alice")));
  });
});

describe("list items", () => {
  beforeEach(seedSharedList);

  test("members can read and write", async () => {
    for (const uid of ["alice", "bob"]) {
      await assertSucceeds(getDoc(doc(as(uid), "lists/alice")));
      await assertSucceeds(getDocs(collection(as(uid), "lists/alice/items")));
      await assertSucceeds(setDoc(doc(as(uid), `lists/alice/items/${uid}-item`), item({ id: `${uid}-item`, completedBy: uid })));
    }
    await assertSucceeds(deleteDoc(doc(as("bob"), "lists/alice/items/item-1")));
  });

  test("non-members can't read or write", async () => {
    await assertFails(getDoc(doc(as("carol"), "lists/alice")));
    await assertFails(getDocs(collection(as("carol"), "lists/alice/items")));
    await assertFails(setDoc(doc(as("carol"), "lists/alice/items/x"), item({ id: "x" })));
    await assertFails(getDocs(collection(signedOut(), "lists/alice/items")));
  });

  test("items are still validated", async () => {
    await assertFails(setDoc(doc(as("bob"), "lists/alice/items/item-2"), item({ id: "item-2", price: 2 })));
    await assertFails(setDoc(doc(as("bob"), "lists/alice/items/item-2"), item({ id: "item-2", completedBy: 7 })));
  });

  test("a list that doesn't exist has no members", async () => {
    await assertFails(getDocs(collection(as("carol"), "lists/nobody/items")));
  });
});

describe("invites", () => {
  test("you can invite people to your own list only", async () => {
    await assertSucceeds(setDoc(doc(as("alice"), "invites/CODE2345"), { listId: "alice", createdBy: "alice", expiresAt: inDays(7) }));
    await assertFails(setDoc(doc(as("alice"), "invites/CODE3456"), { listId: "bob", createdBy: "alice", expiresAt: inDays(7) }));
    await assertFails(setDoc(doc(as("alice"), "invites/CODE4567"), { listId: "alice", createdBy: "alice", expiresAt: inDays(30) }));
    await assertFails(setDoc(doc(as("alice"), "invites/CODE5678"), { listId: "alice", createdBy: "alice", expiresAt: inDays(7), extra: 1 }));
  });

  test("anyone signed in can fetch a code, nobody can list them", async () => {
    await seed("invites/CODE2345", { listId: "alice", createdBy: "alice", expiresAt: inDays(7) });
    await assertSucceeds(getDoc(doc(as("carol"), "invites/CODE2345")));
    await assertFails(getDoc(doc(signedOut(), "invites/CODE2345")));
    await assertFails(getDocs(collection(as("carol"), "invites")));
  });

  test("only the creator can delete an invite; nobody can edit one", async () => {
    await seed("invites/CODE2345", { listId: "alice", createdBy: "alice", expiresAt: inDays(7) });
    await assertFails(deleteDoc(doc(as("carol"), "invites/CODE2345")));
    await assertFails(updateDoc(doc(as("alice"), "invites/CODE2345"), { listId: "carol" }));
    await assertSucceeds(deleteDoc(doc(as("alice"), "invites/CODE2345")));
  });
});

describe("joining", () => {
  beforeEach(async () => {
    await seedSharedList();
    await seed("invites/GOOD2345", { listId: "alice", createdBy: "alice", expiresAt: inDays(7) });
    await seed("invites/OLD23456", { listId: "alice", createdBy: "alice", expiresAt: inDays(-1) });
    await seed("lists/dave", { ownerId: "dave", memberIds: ["dave"] });
    await seed("invites/DAVE2345", { listId: "dave", createdBy: "dave", expiresAt: inDays(7) });
  });

  const join = (uid, code, members = arrayUnion(uid)) =>
    updateDoc(doc(as(uid), "lists/alice"), { memberIds: members, joinCode: code });

  test("works with a valid invite, and the new member sees the items", async () => {
    await assertSucceeds(join("carol", "GOOD2345"));
    await assertSucceeds(getDocs(collection(as("carol"), "lists/alice/items")));
  });

  test("fails without an invite, with an expired one, or with another list's", async () => {
    await assertFails(updateDoc(doc(as("carol"), "lists/alice"), { memberIds: arrayUnion("carol") }));
    await assertFails(join("carol", "NOPE2345"));
    await assertFails(join("carol", "OLD23456"));
    await assertFails(join("carol", "DAVE2345"));
  });

  test("a joiner can only add themselves", async () => {
    await assertFails(join("carol", "GOOD2345", arrayUnion("carol", "eve")));
    await assertFails(join("carol", "GOOD2345", ["carol"]));
    await assertFails(updateDoc(doc(as("carol"), "lists/alice"), { memberIds: arrayUnion("carol"), joinCode: "GOOD2345", ownerId: "carol" }));
  });

  test("the list is capped at 10 members", async () => {
    const eight = ["alice", "bob", "m3", "m4", "m5", "m6", "m7", "m8", "m9"];
    await seed("lists/alice", { ownerId: "alice", memberIds: eight });
    await assertSucceeds(join("carol", "GOOD2345"));
    await assertFails(join("eve", "GOOD2345"));
  });
});

describe("leaving and managing members", () => {
  beforeEach(seedSharedList);

  test("a member can leave", async () => {
    await assertSucceeds(updateDoc(doc(as("bob"), "lists/alice"), { memberIds: arrayRemove("bob") }));
    await assertFails(getDocs(collection(as("bob"), "lists/alice/items")));
  });

  test("a member can't remove others or take over the list", async () => {
    await seed("lists/alice", { ownerId: "alice", memberIds: ["alice", "bob", "carol"] });
    await assertFails(updateDoc(doc(as("bob"), "lists/alice"), { memberIds: arrayRemove("carol") }));
    await assertFails(updateDoc(doc(as("bob"), "lists/alice"), { memberIds: arrayRemove("alice") }));
    await assertFails(updateDoc(doc(as("bob"), "lists/alice"), { ownerId: "bob" }));
  });

  test("the owner can remove members but not themselves, and can't hand the list over", async () => {
    await assertFails(updateDoc(doc(as("alice"), "lists/alice"), { memberIds: arrayRemove("alice") }));
    await assertFails(updateDoc(doc(as("alice"), "lists/alice"), { ownerId: "bob" }));
    await assertSucceeds(updateDoc(doc(as("alice"), "lists/alice"), { memberIds: arrayRemove("bob") }));
  });
});

describe("legacy personal items", () => {
  // The exact batch FirestoreShoppingListService.createOwnList commits, as the user. Rules get()
  // sees the state before the batch, so this fails if item writes need an existing list document.
  test("the migration batch succeeds as the user", async () => {
    await seed("users/alice/items/item-1", item());
    const db = as("alice");
    const batch = writeBatch(db);
    batch.set(doc(db, "lists/alice"), { ownerId: "alice", memberIds: ["alice"] });
    batch.set(doc(db, "lists/alice/items/item-1"), item());
    batch.set(doc(db, "users/alice"), { activeListId: "alice" }, { merge: true });
    await assertSucceeds(batch.commit());
  });

  test("nobody else can run a migration into your list", async () => {
    const db = as("bob");
    const batch = writeBatch(db);
    batch.set(doc(db, "lists/alice"), { ownerId: "alice", memberIds: ["alice"] });
    batch.set(doc(db, "lists/alice/items/item-1"), item());
    await assertFails(batch.commit());
  });

  test("stay readable by their owner for migration", async () => {
    await seed("users/alice/items/item-1", item());
    await assertSucceeds(getDocs(collection(as("alice"), "users/alice/items")));
    await assertFails(getDocs(collection(as("bob"), "users/alice/items")));
  });
});
