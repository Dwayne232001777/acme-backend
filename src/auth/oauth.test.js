const sinon = require("sinon");
describe("OAuth flow", () => {
  let clock;
  beforeEach(() => { clock = sinon.useFakeTimers(); });
  afterEach(() => { clock.restore(); });
  it("handles Google callback", async () => {
    const result = await mockProvider.callback("fake-code");
    clock.tick(5000);
    expect(result.accessToken).to.exist;
  });
});
