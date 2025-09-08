import * as functions from "firebase-functions";
import * as functionsV1 from "firebase-functions/v1";
import * as admin from "firebase-admin";
import sgMail from "@sendgrid/mail";
import * as crypto from "crypto";

// Ensure the Admin SDK is initialised exactly once per runtime.
if (!admin.apps.length) {
  admin.initializeApp();
}

// Read the SendGrid key from env. Configure via:
//   firebase functions:config:set sendgrid.key="YOUR_API_KEY"
const SENDGRID_API_KEY =
  process.env.SENDGRID_API_KEY || functions.config().sendgrid?.key;
if (!SENDGRID_API_KEY) {
  console.warn(
    "SendGrid API key not found in env or functions config; " +
      "email will not be sent."
  );
}
sgMail.setApiKey(SENDGRID_API_KEY);

/**
 * Scheduled function that runs daily and queues feedback-request emails for
 * users who generated a plan >=24h ago and have not been asked yet.
 */
export const scheduleFeedback = functionsV1.pubsub
  .schedule("every 24 hours")
  // Keep resource usage small – adjust region / memory if needed.
  .timeZone("Etc/UTC")
  .onRun(async () => {
    const firestore = admin.firestore();
    const twentyFourHrsAgo = Date.now() - 24 * 60 * 60 * 1000;

    const snap = await firestore
      .collection("users")
      .where("lastPlanGeneratedAt", "<=", twentyFourHrsAgo)
      .where("feedbackAsked", "==", false)
      .get();

    if (snap.empty) return null;

    const batch = firestore.batch();
    snap.forEach((doc) => {
      const data = doc.data() as { email?: string; displayName?: string };
      if (!data.email) return; // Skip if we have no email on record.

      const token = crypto.randomBytes(16).toString("hex");

      // Queue a feedback request document.
      batch.set(firestore.collection("feedbackQueue").doc(), {
        uid: doc.id,
        email: data.email,
        displayName: data.displayName || "there",
        token,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Mark the user so we don't ask again.
      batch.update(doc.ref, {feedbackAsked: true});
    });

    await batch.commit();
    return null;
  });

/**
 * Firestore trigger – sends the actual feedback email when a queue doc is
 * created.
 */
export const sendFeedbackEmail = functionsV1.firestore
  .document("feedbackQueue/{id}")
  .onCreate(async (snap: functionsV1.firestore.QueryDocumentSnapshot) => {
    if (!SENDGRID_API_KEY) return null; // Skip if no key, avoids crashes.

    const {email, displayName, token, uid} = snap.data() as {
      email: string;
      displayName: string;
      token: string;
      uid: string;
    };

    const formUrl = process.env.FEEDBACK_FORM_URL ?? "https://forms.gle/your-form";
    const feedbackUrl = `${formUrl}?uid=${uid}&token=${token}`;

    const msg: sgMail.MailDataRequired = {
      to: email,
      from: {
        email: "hello@dategenie.app",
        name: "Victoria from DateGenie",
      },
      subject: "Quick feedback about DateGenie 💌",
      /* eslint-disable max-len */
      html: `
        <p>Hi ${displayName},</p>
        <p>Could you spare 1 minute to help us improve DateGenie?</p>
        <ol>
          <li>What do you <strong>like</strong> about the app?</li>
          <li>What do you <strong>dislike</strong> about the app?</li>
          <li>What’s <strong>confusing</strong> or unclear?</li>
          <li>What do you <strong>wish</strong> you could do with the app?</li>
          <li>Any other questions or comments?</li>
        </ol>
        <p>You can answer in two ways:</p>
        <ul>
          <li><strong>Quick form</strong> (preferred): <a href="${feedbackUrl}">open the form</a></li>
          <li><strong>Reply to this email</strong> with your answers</li>
        </ul>
        <p>Thanks for helping us make DateGenie better!<br/>— Victoria & the DateGenie Team</p>
        <p style="font-size:12px;color:#888;">If you’d rather not receive these emails, you can <a href="https://dategenie.app/unsubscribe?uid=${uid}">unsubscribe here</a>.</p>
      `,
      /* eslint-enable max-len */
    };

    try {
      await sgMail.send(msg);
      await snap.ref.update({
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      console.error("Failed to send feedback email", err);
      await snap.ref.update({
        error: (err as Error).message,
        errorAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return null;
  });
