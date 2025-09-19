/*
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

// Start writing functions
// https://firebase.google.com/docs/functions/typescript

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.

export {generateCampusPlans} from "./generateCampusPlans";
export {voiceAssistant} from "./voiceAssistant";
export {getAssemblyToken} from "./getAssemblyToken";
export {startVeoForJob} from "./veo/startVeoForJob";
export {validateReceipt} from "./validateReceipt";
// Ad generation endpoints disabled: removing exports to prevent use in app
// export {createAdJob} from "./veo/createAdJob";
// export {adPromptBuilder} from "./veo/adPromptBuilder";
// export {conversationToBrief} from "./veo/conversationToBrief";
// export {createAdFromConversation} from "./veo/createAdFromConversation";
// export {onAdJobQueued} from "./veo/onAdJobQueued";
export {generateStoryboardPlan} from "./generateStoryboardPlan";
export {generateStoryboardPlanFromScene} from "./generateStoryboardPlanFromScene";
export {generateStoryboardImages} from "./generateStoryboardImages";
export {generateCharacterImage} from "./generateCharacterImage";
export {createStoryboardJob} from "./veo/createStoryboardJob";
export {createStoryboardJobV2} from "./veo/createStoryboardJobV2";
export {wanI2vFast} from "./wanI2VFast";
export {startStoryboardJobV2} from "./veo/startStoryboardJobV2";
export {veoDirect} from "./veo/veoDirect";
export {saveStoryboardSet} from "./saveStoryboardSet";
export {enqueueSceneVideo} from "./enqueueSceneVideo";
export {runSceneVideo} from "./runSceneVideo";
