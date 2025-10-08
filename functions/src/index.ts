import { onCall, HttpsError } from "firebase-functions/v2/https"; // <-- NEW v2 import
import * as admin from "firebase-admin";
import * as jwt from "jsonwebtoken";
import { logger } from "firebase-functions"; // <-- NEW v2 logger

admin.initializeApp();
const db = admin.firestore();

// Use process.env to access environment variables in v2
const JWT_SECRET = process.env.JWT_SECRET;

const spotToPayload = (spotData: admin.firestore.DocumentData) => {
    return {
        name: spotData.name,
        address: spotData.address,
        latitude: spotData.latitude,
        longitude: spotData.longitude,
        category: spotData.category,
        phoneNumber: spotData.phoneNumber,
        websiteURL: spotData.websiteURL,
        notes: spotData.notes,
        sourceURL: spotData.sourceURL,
    };
};

/**
 * Creates a short-lived, signed JWT for sharing a spot or collection.
 */
export const generateShareToken = onCall(async (request) => { // <-- NEW v2 syntax
  if (!request.auth) {
    throw new HttpsError( // <-- NEW v2 syntax
      "unauthenticated",
      "The function must be called while authenticated.",
    );
  }

  const { targetType, targetId } = request.data;

  if (!JWT_SECRET) {
      logger.error("JWT_SECRET is not defined in environment variables.");
      throw new HttpsError("internal", "JWT secret is not configured.");
  }
  
  if (targetType !== "spot" && targetType !== "collection") {
      throw new HttpsError(
        "invalid-argument",
        "targetType must be 'spot' or 'collection'.",
      );
  }

  const payload = {
    uid: request.auth.uid,
    type: targetType,
    id: targetId,
  };

  const token = jwt.sign(payload, JWT_SECRET, { expiresIn: "30d" });
  return { token: token };
});

/**
 * Verifies a share token (JWT) and fetches the corresponding data from Firestore.
 */
export const verifyAndFetchSharedData = onCall(async (request) => {
  const { token } = request.data;
  if (!token) {
    throw new HttpsError("invalid-argument", "The function must be called with a 'token' argument.");
  }
  if (!JWT_SECRET) {
    logger.error("JWT_SECRET is not defined in environment variables.");
    throw new HttpsError("internal", "JWT secret is not configured.");
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as { uid: string; type: "spot" | "collection"; id: string; };
    const { uid, type, id } = decoded;

    const senderUserRecord = await admin.auth().getUser(uid);
    const senderName = senderUserRecord.displayName || "A SweetSpots User";

    if (type === "spot") {
        const doc = await db.collection("users").doc(uid).collection("spots").doc(id).get();
        if (!doc.exists || !doc.data()) {
            throw new HttpsError("not-found", "Spot not found.");
        }
        // Transform the Spot data to the payload format before returning
        const payload = spotToPayload(doc.data()!);
        return { type: "spot", data: { ...payload, senderName: senderName } };

    } else if (type === "collection") {
        const collectionDoc = await db.collection("users").doc(uid).collection("spotCollections").doc(id).get();
        if (!collectionDoc.exists || !collectionDoc.data()) {
            throw new HttpsError("not-found", "Collection not found.");
        }
        const collectionData = collectionDoc.data()!;

        // Fetch all spots that belong to this collection
        const spotsSnapshot = await db.collection("users").doc(uid).collection("spots")
            .where("collectionIds", "array-contains", id).get();
        
        // Use the helper to format each spot into a payload
        const spotPayloads = spotsSnapshot.docs.map(doc => spotToPayload(doc.data()));

        // Build the final collection payload, including the emoji
        const collectionPayload = {
            collectionName: collectionData.name,
            collectionDescription: collectionData.descriptionText,
            emoji: collectionData.emoji, // Include the emoji
            spots: spotPayloads,
        };
        
        return { type: "collection", data: { ...collectionPayload, senderName: senderName } };
    } else {
        throw new HttpsError("invalid-argument", "Invalid share type in token.");
    }
  } catch (error) {
    logger.error("Error verifying token:", error);
    throw new HttpsError("permission-denied", "Invalid or expired share link.");
  }
});