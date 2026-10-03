// Shared lists and invites (Phase 6), run against the Firestore emulator.
import { after, before, beforeEach, describe, test } from "node:test";
import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import {
  arrayRemove,
  arrayUnion,
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  Timestamp,
  updateDoc,
  where,
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

/// The batch FirestoreShoppingListService.joinList commits: the list only gains the joiner, and the
/// proof of invite goes in the joiner's own user document.
function join(uid, code, members = arrayUnion(uid)) {
  const db = as(uid);
  const batch = writeBatch(db);
  batch.update(doc(db, "lists/alice"), { memberIds: members });
  batch.set(doc(db, `users/${uid}`), { activeListId: "alice", joinCode: code }, { merge: true });
  return batch.commit();
}

/// The batch FirestoreShoppingListService.leaveList commits, which also clears the proof of invite.
function leave(uid) {
  const db = as(uid);
  const batch = writeBatch(db);
  batch.update(doc(db, "lists/alice"), { memberIds: arrayRemove(uid) });
  batch.set(doc(db, `users/${uid}`), { activeListId: uid, joinCode: deleteField() }, { merge: true });
  return batch.commit();
}

describe("creating a list", () => {
  test("you can create your own list", async () => {
    await assertSucceeds(setDoc(doc(as("alice"), "lists/alice"), { ownerId: "alice", memberIds: ["alice"] }));
  });

  test("you can't create someone else's list or add members at creation", async () => {
    await assertFails(setDoc(doc(as("alice"), "lists/bob"), { ownerId: "bob", memberIds: ["bob"] }));
    await assertFails(setDoc(doc(as("alice"), "lists/alice"), { ownerId: "alice", memberIds: ["alice", "carol"] }));
    await assertFails(setDoc(doc(signedOut(), "lists/alice"), { ownerId: "alice", memberIds: ["alice"] }));
    await assertFails(setDoc(doc(as("alice"), "lists/alice"), { ownerId: "alice", memberIds: ["alice"], joinCode: "GOOD2345" }));
  });

  test("only the owner can delete their list, and then its members lose access", async () => {
    await seedSharedList();
    await assertFails(deleteDoc(doc(as("bob"), "lists/alice")));
    await assertFails(deleteDoc(doc(as("carol"), "lists/alice")));
    await assertFails(deleteDoc(doc(signedOut(), "lists/alice")));
    await assertSucceeds(deleteDoc(doc(as("alice"), "lists/alice")));
    await assertFails(getDocs(collection(as("bob"), "lists/alice/items")));
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

  test("completedBy can only name the writer, or stay as it was", async () => {
    await assertFails(setDoc(doc(as("bob"), "lists/alice/items/item-2"), item({ id: "item-2", isCompleted: true, completedBy: "alice" })));
    await assertFails(updateDoc(doc(as("bob"), "lists/alice/items/item-1"), { isCompleted: true, completedBy: "alice" }));
    await assertSucceeds(updateDoc(doc(as("bob"), "lists/alice/items/item-1"), { isCompleted: true, completedBy: "bob" }));

    // alice checked it off: bob can edit it and keep her name on it, but not put someone else's.
    await seed("lists/alice/items/item-1", item({ isCompleted: true, completedBy: "alice" }));
    await assertSucceeds(setDoc(doc(as("bob"), "lists/alice/items/item-1"), item({ title: "Oat milk", isCompleted: true, completedBy: "alice" })));
    await assertFails(updateDoc(doc(as("bob"), "lists/alice/items/item-1"), { completedBy: "carol" }));
    await assertSucceeds(updateDoc(doc(as("bob"), "lists/alice/items/item-1"), { completedBy: deleteField() }));

    // Unchecking it the way the app does: the whole item, without completedBy.
    await seed("lists/alice/items/item-1", item({ isCompleted: true, completedBy: "alice" }));
    await assertSucceeds(setDoc(doc(as("bob"), "lists/alice/items/item-1"), item({ isCompleted: false })));
  });

  test("dates must be timestamps, and both are required", async () => {
    const { createdAt, ...noCreatedAt } = item({ id: "item-2" });
    const { updatedAt, ...noUpdatedAt } = item({ id: "item-2" });
    await assertFails(setDoc(doc(as("bob"), "lists/alice/items/item-2"), noCreatedAt));
    await assertFails(setDoc(doc(as("bob"), "lists/alice/items/item-2"), noUpdatedAt));
    await assertFails(setDoc(doc(as("bob"), "lists/alice/items/item-2"), item({ id: "item-2", createdAt: "x".repeat(100_000) })));
    await assertFails(setDoc(doc(as("bob"), "lists/alice/items/item-2"), item({ id: "item-2", updatedAt: { a: [1, 2, 3] } })));
    await assertFails(updateDoc(doc(as("bob"), "lists/alice/items/item-1"), { updatedAt: 1_700_000_000 }));
    await assertSucceeds(updateDoc(doc(as("bob"), "lists/alice/items/item-1"), { updatedAt: Timestamp.now() }));
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

  test("anyone signed in can fetch a code, but can only list their own", async () => {
    await seed("invites/CODE2345", { listId: "alice", createdBy: "alice", expiresAt: inDays(7) });
    await assertSucceeds(getDoc(doc(as("carol"), "invites/CODE2345")));
    await assertFails(getDoc(doc(signedOut(), "invites/CODE2345")));
    await assertFails(getDocs(collection(as("carol"), "invites")));
    await assertFails(getDocs(query(collection(as("carol"), "invites"), where("createdBy", "==", "alice"))));
    await assertFails(getDocs(collection(as("alice"), "invites")));
    const own = await assertSucceeds(getDocs(query(collection(as("alice"), "invites"), where("createdBy", "==", "alice"))));
    if (own.size !== 1) throw new Error(`expected alice's 1 invite, got ${own.size}`);
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

  test("fails when the proof isn't in the joiner's own user document", async () => {
    // Saved without a code, e.g. by an earlier sign-in.
    await seed("users/carol", { activeListId: "carol" });
    await assertFails(updateDoc(doc(as("carol"), "lists/alice"), { memberIds: arrayUnion("carol") }));
    // The way older app versions joined: the code on the list itself.
    await assertFails(updateDoc(doc(as("carol"), "lists/alice"), { memberIds: arrayUnion("carol"), joinCode: "GOOD2345" }));
    // Someone else's user document.
    await seed("users/eve", { activeListId: "alice", joinCode: "GOOD2345" });
    await assertFails(updateDoc(doc(as("carol"), "lists/alice"), { memberIds: arrayUnion("carol") }));
  });

  test("fails when the proof isn't a code", async () => {
    for (const code of [12345678, ["GOOD2345"], null, "", "GOOD2345/x/y", "../invites/GOOD2345"]) {
      await assertFails(join("carol", code));
    }
  });

  test("a joiner can only add themselves", async () => {
    await assertFails(join("carol", "GOOD2345", arrayUnion("carol", "eve")));
    await assertFails(join("carol", "GOOD2345", ["carol"]));
    const db = as("carol");
    const batch = writeBatch(db);
    batch.update(doc(db, "lists/alice"), { memberIds: arrayUnion("carol"), ownerId: "carol" });
    batch.set(doc(db, "users/carol"), { activeListId: "alice", joinCode: "GOOD2345" }, { merge: true });
    await assertFails(batch.commit());
  });

  test("the list is capped at 10 members", async () => {
    const eight = ["alice", "bob", "m3", "m4", "m5", "m6", "m7", "m8", "m9"];
    await seed("lists/alice", { ownerId: "alice", memberIds: eight });
    await assertSucceeds(join("carol", "GOOD2345"));
    await assertFails(join("eve", "GOOD2345"));
  });

  test("someone already on the list only switches to it", async () => {
    // The app checks membership first and then only sets activeListId.
    await assertSucceeds(getDoc(doc(as("bob"), "lists/alice")));
    await assertSucceeds(setDoc(doc(as("bob"), "users/bob"), { activeListId: "alice" }, { merge: true }));
    await assertFails(join("bob", "GOOD2345"));
  });
});

describe("a joinCode stored on the list by older app versions", () => {
  beforeEach(async () => {
    await seed("lists/alice", { ownerId: "alice", memberIds: ["alice", "bob"], joinCode: "GOOD2345" });
    await seed("lists/alice/items/item-1", item());
    await seed("invites/GOOD2345", { listId: "alice", createdBy: "alice", expiresAt: inDays(7) });
  });

  test("lets nobody in without a code", async () => {
    await assertFails(updateDoc(doc(as("mallory"), "lists/alice"), { memberIds: arrayUnion("mallory") }));
    await assertFails(getDocs(collection(as("mallory"), "lists/alice/items")));
  });

  test("doesn't let a member who left, or was removed, back in", async () => {
    await assertSucceeds(updateDoc(doc(as("bob"), "lists/alice"), { memberIds: arrayRemove("bob") }));
    await assertFails(updateDoc(doc(as("bob"), "lists/alice"), { memberIds: arrayUnion("bob") }));

    await seed("lists/alice", { ownerId: "alice", memberIds: ["alice", "carol"], joinCode: "GOOD2345" });
    await assertSucceeds(updateDoc(doc(as("alice"), "lists/alice"), { memberIds: arrayRemove("carol") }));
    await assertFails(updateDoc(doc(as("carol"), "lists/alice"), { memberIds: arrayUnion("carol") }));
  });

  test("the owner can remove it, but not change or add one", async () => {
    await assertFails(updateDoc(doc(as("bob"), "lists/alice"), { joinCode: deleteField() }));
    await assertFails(updateDoc(doc(as("alice"), "lists/alice"), { joinCode: "OTHR2345" }));
    await assertSucceeds(updateDoc(doc(as("alice"), "lists/alice"), { joinCode: deleteField() }));
    await assertFails(updateDoc(doc(as("alice"), "lists/alice"), { joinCode: "GOOD2345" }));
  });
});

describe("leaving and managing members", () => {
  beforeEach(seedSharedList);

  test("a member can leave", async () => {
    await assertSucceeds(updateDoc(doc(as("bob"), "lists/alice"), { memberIds: arrayRemove("bob") }));
    await assertFails(getDocs(collection(as("bob"), "lists/alice/items")));
  });

  test("the app's leave clears the proof, so coming back takes a code again", async () => {
    await seed("invites/GOOD2345", { listId: "alice", createdBy: "alice", expiresAt: inDays(7) });
    await assertSucceeds(join("carol", "GOOD2345"));
    await assertSucceeds(leave("carol"));
    await assertFails(updateDoc(doc(as("carol"), "lists/alice"), { memberIds: arrayUnion("carol") }));
    await assertSucceeds(join("carol", "GOOD2345"));
  });

  test("a leaver's leftover proof stops working once the invite is revoked", async () => {
    await seed("invites/GOOD2345", { listId: "alice", createdBy: "alice", expiresAt: inDays(7) });
    await assertSucceeds(join("carol", "GOOD2345"));
    // Left without clearing it (an older app version, or on purpose).
    await assertSucceeds(updateDoc(doc(as("carol"), "lists/alice"), { memberIds: arrayRemove("carol") }));
    await assertSucceeds(deleteDoc(doc(as("alice"), "invites/GOOD2345")));
    await assertFails(updateDoc(doc(as("carol"), "lists/alice"), { memberIds: arrayUnion("carol") }));
    await assertFails(join("carol", "GOOD2345"));
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

describe("deleting an account", () => {
  beforeEach(async () => {
    await seedSharedList();
    await seed("invites/GOOD2345", { listId: "alice", createdBy: "alice", expiresAt: inDays(7) });
    await seed("users/alice", { activeListId: "alice" });
    await seed("users/alice/preferences/main", { dailyListReminderEnabled: true });
    await seed("users/alice/items/old-1", item({ id: "old-1" }));
  });

  test("the owner can delete what FirestoreShoppingListService.deleteAllData deletes, in one batch", async () => {
    const db = as("alice");
    const invites = await getDocs(query(collection(db, "invites"), where("createdBy", "==", "alice")));
    const items = await getDocs(collection(db, "lists/alice/items"));
    const legacy = await getDocs(collection(db, "users/alice/items"));
    const batch = writeBatch(db);
    for (const snapshot of [...invites.docs, ...items.docs, ...legacy.docs]) {
      batch.delete(snapshot.ref);
    }
    for (const path of ["lists/alice", "users/alice/preferences/main", "users/alice"]) {
      batch.delete(doc(db, path));
    }
    await assertSucceeds(batch.commit());
    // bob was on alice's list; it's gone for him too.
    await assertFails(getDocs(collection(as("bob"), "lists/alice/items")));
  });

  test("nobody else can delete your list, invites or user data", async () => {
    await assertFails(deleteDoc(doc(as("bob"), "lists/alice")));
    await assertFails(deleteDoc(doc(as("bob"), "invites/GOOD2345")));
    await assertFails(deleteDoc(doc(as("bob"), "users/alice")));
    await assertFails(deleteDoc(doc(as("bob"), "users/alice/preferences/main")));
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

  // What FirestoreShoppingListService.migratableItem makes of an item saved before the rules
  // checked it: text cut to the limits in UTF-16 units (an emoji takes two), a foreign
  // completedBy dropped. One item left as it was fails the whole batch.
  test("the migration's cleaned-up items pass, and the raw legacy ones don't", async () => {
    const trimmed = item({
      id: "item-2",
      title: "a" + "😀".repeat(249),
      notes: "n".repeat(2000),
      aisle: "é".repeat(200),
      isCompleted: true,
      completedBy: "alice",
    });
    const migrationBatch = (items) => {
      const db = as("alice");
      const batch = writeBatch(db);
      batch.set(doc(db, "lists/alice"), { ownerId: "alice", memberIds: ["alice"] });
      for (const data of items) batch.set(doc(db, `lists/alice/items/${data.id}`), data);
      batch.set(doc(db, "users/alice"), { activeListId: "alice" }, { merge: true });
      return batch.commit();
    };
    await assertFails(migrationBatch([item(), { ...trimmed, title: trimmed.title + "😀" }]));
    await assertFails(migrationBatch([item(), { ...trimmed, completedBy: "bob" }]));
    await assertSucceeds(migrationBatch([item(), trimmed]));
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
