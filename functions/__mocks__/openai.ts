// Jest manual mock for the `openai` package used in generatePlans.
// It returns a deterministic fake chat completion so tests don't call the real API.
export default class OpenAI {
  public chat = {
    completions: {
      create: async () => ({
        choices: [
          {
            message: {
              content: JSON.stringify({plans:[
                { title: "Mock date", itinerary: "We walk by the river", venueName: "Central Park", romance: 0.9, novelty: 0.7 },
                { title: "Sunset picnic", itinerary: "Picnic at the meadow", venueName: "Meadow Park", romance: 0.8, novelty: 0.6 },
                { title: "Museum stroll", itinerary: "Explore art", venueName: "Met Museum", romance: 0.7, novelty: 0.5 }
              ]})
            },
          },
        ],
      }),
    },
  };

  public images = {
    generate: async () => ({data: [{url: "https://example.com/fake.png"}]}),
  };
}
