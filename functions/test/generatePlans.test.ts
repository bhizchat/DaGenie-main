// Set env before loading function

const addMock = jest.fn().mockResolvedValue({id: "1"});
// Mock Firestore to avoid needing emulator
jest.mock("firebase-admin/firestore", () => {
  return {
    getFirestore: () => ({
      settings: jest.fn(),
      collection: () => ({
        add: addMock,
        get: jest.fn().mockResolvedValue({size: 1, docs: [{data: () => ({event: "generate_plan"})}]}),
      }),
    }),
  };
});

process.env.FIRESTORE_EMULATOR_HOST = "localhost:8080";
process.env.GOOGLE_CLOUD_PROJECT = "demo-project";
process.env.OPENAI_KEY = "test";
process.env.GOOGLE_PLACES_KEY = "";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const {generatePlans} = require("../src/generatePlans");
// eslint-disable-next-line @typescript-eslint/no-var-requires
const functionsTest = require("firebase-functions-test");
import * as admin from "firebase-admin";
import {Request, Response} from "express";



const fft = functionsTest({projectId: "demo-project"});

beforeAll(() => {
  if (!admin.apps.length) {
    const dummyCred = admin.credential.cert({
      projectId: "demo-project",
      clientEmail: "test@test.com",
      privateKey: "dummy",
    } as any);
    admin.initializeApp({projectId: "demo-project", credential: dummyCred});
  }
});

afterAll(async () => {
  await admin.app().delete();
  fft.cleanup();
});

function mockReqBody(body: any): any {
  return {
    body,
    headers: {},
    rawBody: Buffer.from(""),
    method: "POST",
  } as unknown as Request;
}

function mockRes() {
  const json = jest.fn();
  const status = jest.fn(() => ({json})) as any;
  const res = {status} as unknown as Response;
  return {res, json, status};
}

jest.setTimeout(20000);

describe("generatePlans Cloud Function", () => {
  it("writes an analyticsEvents doc", async () => {
    const {res, json} = mockRes();
    await generatePlans(mockReqBody({location: "NYC"}), res);
    expect(json).toHaveBeenCalled();

    expect(addMock).toHaveBeenCalled();
  });
});
