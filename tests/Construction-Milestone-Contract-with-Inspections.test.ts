import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

const contractName = "Construction-Milestone-Contract-with-Inspections";

describe("Construction Milestone Contract Tests", () => {
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  describe("Basic Contract Functions", () => {
    it("should allow owner to add milestone", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "add-milestone",
        [
          Cl.stringAscii("Foundation work"),
          Cl.uint(50000),
          Cl.principal(wallet1),
          Cl.uint(1000),
        ],
        deployer
      );
      expect(result).toBeOk();
      expect(result).toBeUint(1);
    });

    it("should register inspector", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "register-inspector",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(result).toBeOk();
      expect(result).toBeBool(true);
    });
  });

  describe("Contractor Quality Rating System", () => {
    beforeEach(() => {
      // Setup: Add milestone, register inspector, mark milestone as completed and approved
      simnet.callPublicFn(
        contractName,
        "add-milestone",
        [
          Cl.stringAscii("Test milestone"),
          Cl.uint(10000),
          Cl.principal(wallet1),
          Cl.uint(1000),
        ],
        deployer
      );
      
      simnet.callPublicFn(
        contractName,
        "register-inspector",
        [Cl.principal(wallet1)],
        deployer
      );
      
      simnet.callPublicFn(
        contractName,
        "mark-milestone-completed",
        [Cl.uint(1)],
        deployer
      );
      
      simnet.callPublicFn(
        contractName,
        "approve-milestone",
        [Cl.uint(1)],
        wallet1
      );
    });

    it("should allow inspector to rate contractor", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "rate-contractor",
        [
          Cl.principal(wallet2),
          Cl.uint(4),
          Cl.uint(1),
          Cl.stringAscii("Good work quality")
        ],
        wallet1
      );
      expect(result).toBeOk();
      expect(result).toBeUint(1);
    });

    it("should reject invalid rating values", () => {
      const { result: tooLow } = simnet.callPublicFn(
        contractName,
        "rate-contractor",
        [
          Cl.principal(wallet2),
          Cl.uint(0),
          Cl.uint(1),
          Cl.stringAscii("Invalid rating")
        ],
        wallet1
      );
      expect(tooLow).toBeErr();
      expect(tooLow).toBeUint(117); // err-invalid-rating

      const { result: tooHigh } = simnet.callPublicFn(
        contractName,
        "rate-contractor",
        [
          Cl.principal(wallet2),
          Cl.uint(6),
          Cl.uint(1),
          Cl.stringAscii("Invalid rating")
        ],
        wallet1
      );
      expect(tooHigh).toBeErr();
      expect(tooHigh).toBeUint(117); // err-invalid-rating
    });

    it("should reject unauthorized rater", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "rate-contractor",
        [
          Cl.principal(wallet2),
          Cl.uint(4),
          Cl.uint(1),
          Cl.stringAscii("Unauthorized attempt")
        ],
        wallet3 // wallet3 is not inspector or owner
      );
      expect(result).toBeErr();
      expect(result).toBeUint(120); // err-unauthorized-rater
    });

    it("should prevent duplicate ratings for same milestone", () => {
      // First rating should succeed
      const { result: first } = simnet.callPublicFn(
        contractName,
        "rate-contractor",
        [
          Cl.principal(wallet2),
          Cl.uint(4),
          Cl.uint(1),
          Cl.stringAscii("First rating")
        ],
        wallet1
      );
      expect(first).toBeOk();

      // Second rating should fail
      const { result: second } = simnet.callPublicFn(
        contractName,
        "rate-contractor",
        [
          Cl.principal(wallet2),
          Cl.uint(3),
          Cl.uint(1),
          Cl.stringAscii("Duplicate rating")
        ],
        wallet1
      );
      expect(second).toBeErr();
      expect(second).toBeUint(118); // err-already-rated
    });

    it("should allow owner to update blacklist threshold", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "update-rating-threshold",
        [Cl.uint(150)], // 1.5 stars
        deployer
      );
      expect(result).toBeOk();
      expect(result).toBeBool(true);
    });

    it("should reject invalid threshold values", () => {
      const { result: tooLow } = simnet.callPublicFn(
        contractName,
        "update-rating-threshold",
        [Cl.uint(50)], // Below minimum
        deployer
      );
      expect(tooLow).toBeErr();
      expect(tooLow).toBeUint(122); // err-invalid-threshold

      const { result: tooHigh } = simnet.callPublicFn(
        contractName,
        "update-rating-threshold",
        [Cl.uint(600)], // Above maximum
        deployer
      );
      expect(tooHigh).toBeErr();
      expect(tooHigh).toBeUint(122); // err-invalid-threshold
    });

    it("should allow manual blacklist management", () => {
      const contractor = wallet2;
      
      // Manually blacklist contractor
      const { result: blacklist } = simnet.callPublicFn(
        contractName,
        "manually-blacklist-contractor",
        [Cl.principal(contractor), Cl.bool(true)],
        deployer
      );
      expect(blacklist).toBeOk();
      expect(blacklist).toBeBool(true);
      
      // Check blacklist status
      const { result: isBlacklisted } = simnet.callReadOnlyFn(
        contractName,
        "is-contractor-blacklisted",
        [Cl.principal(contractor)],
        deployer
      );
      expect(isBlacklisted).toBeBool(true);
      
      // Remove from blacklist
      const { result: unblacklist } = simnet.callPublicFn(
        contractName,
        "manually-blacklist-contractor",
        [Cl.principal(contractor), Cl.bool(false)],
        deployer
      );
      expect(unblacklist).toBeOk();
      expect(unblacklist).toBeBool(true);
    });

    it("should provide comprehensive rating statistics", () => {
      // Add some ratings first
      simnet.callPublicFn(
        contractName,
        "rate-contractor",
        [Cl.principal(wallet2), Cl.uint(5), Cl.uint(1), Cl.stringAscii("Excellent work")],
        wallet1
      );
      
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-rating-system-stats",
        [],
        deployer
      );
      
      expect(result).toBeTuple({
        "total-ratings-submitted": Cl.uint(1),
        "current-blacklist-threshold": Cl.uint(200),
        "threshold-in-stars": Cl.uint(2),
      });
    });

    it("should track rating history correctly", () => {
      const contractor = wallet2;
      const rater = wallet1;
      const milestoneId = 1;
      
      // Initially should not have rated
      const { result: beforeRating } = simnet.callReadOnlyFn(
        contractName,
        "has-rated-milestone",
        [Cl.principal(contractor), Cl.principal(rater), Cl.uint(milestoneId)],
        deployer
      );
      expect(beforeRating).toBeBool(false);
      
      // Add rating
      simnet.callPublicFn(
        contractName,
        "rate-contractor",
        [Cl.principal(contractor), Cl.uint(4), Cl.uint(milestoneId), Cl.stringAscii("Good work")],
        rater
      );
      
      // Should now show as rated
      const { result: afterRating } = simnet.callReadOnlyFn(
        contractName,
        "has-rated-milestone",
        [Cl.principal(contractor), Cl.principal(rater), Cl.uint(milestoneId)],
        deployer
      );
      expect(afterRating).toBeBool(true);
    });

    it("should get contractor profile correctly", () => {
      const contractor = wallet2;
      
      // Add a rating first
      simnet.callPublicFn(
        contractName,
        "rate-contractor",
        [Cl.principal(contractor), Cl.uint(4), Cl.uint(1), Cl.stringAscii("Good work")],
        wallet1
      );
      
      // Get contractor profile
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-contractor-profile",
        [Cl.principal(contractor)],
        deployer
      );
      
      expect(result).toBeSome();
    });

    it("should get contractor rating details", () => {
      // Add a rating first
      simnet.callPublicFn(
        contractName,
        "rate-contractor",
        [Cl.principal(wallet2), Cl.uint(5), Cl.uint(1), Cl.stringAscii("Excellent work")],
        wallet1
      );
      
      // Get rating details
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-contractor-rating",
        [Cl.uint(1)],
        deployer
      );
      
      expect(result).toBeSome();
    });
  });
});


