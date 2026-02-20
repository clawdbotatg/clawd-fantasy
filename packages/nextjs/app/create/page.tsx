"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { formatEther, parseEther } from "viem";
import { useAccount } from "wagmi";
import { ThreeButtonFlow } from "~~/components/clawd-fantasy/ThreeButtonFlow";
import { useScaffoldWriteContract } from "~~/hooks/scaffold-eth";
import { useDeployedContractInfo } from "~~/hooks/scaffold-eth";

const CreateLeague = () => {
  const router = useRouter();
  useAccount();

  const [entryFee, setEntryFee] = useState("100");
  const [duration, setDuration] = useState(86400); // 1 day
  const [maxPlayers, setMaxPlayers] = useState(4);
  const [maxPicks, setMaxPicks] = useState(1);
  const [houseCut, setHouseCut] = useState(5); // percent
  const [picks, setPicks] = useState<string[]>([""]);

  const entryFeeWei = entryFee ? parseEther(entryFee) : 0n;
  const houseCutBps = BigInt(houseCut * 100);

  const { data: fantasyLeagueInfo } = useDeployedContractInfo({ contractName: "FantasyLeague" });
  const spender = fantasyLeagueInfo?.address || "";

  const { writeContractAsync: createLeagueAsync, isMining } = useScaffoldWriteContract({
    contractName: "FantasyLeague",
  });

  const validPicks = picks.filter(p => p.length === 42 && p.startsWith("0x"));
  const canCreate = validPicks.length >= 1 && validPicks.length <= maxPicks && entryFeeWei > 0n;

  const estimatedPot = entryFeeWei * BigInt(maxPlayers);
  const estimatedBurn = (estimatedPot * houseCutBps) / 10000n;

  const handleCreate = async () => {
    if (!canCreate) return;
    try {
      await createLeagueAsync({
        functionName: "createLeague",
        args: [
          entryFeeWei,
          BigInt(duration),
          BigInt(maxPlayers),
          BigInt(maxPicks),
          houseCutBps,
          validPicks as `0x${string}`[],
        ],
      });
      router.push("/");
    } catch (e) {
      console.error("Create league failed:", e);
    }
  };

  return (
    <div className="flex flex-col items-center px-4 py-8 max-w-xl mx-auto w-full">
      <h1 className="text-2xl font-bold mb-6">Create League 🦞</h1>

      <div className="w-full space-y-4">
        {/* Entry Fee */}
        <div className="form-control">
          <label className="label">
            <span className="label-text">Entry Fee (CLAWD)</span>
          </label>
          <input
            type="number"
            className="input input-bordered w-full"
            value={entryFee}
            onChange={e => setEntryFee(e.target.value)}
            min="1"
            placeholder="100"
          />
        </div>

        {/* Duration */}
        <div className="form-control">
          <label className="label">
            <span className="label-text">Duration</span>
          </label>
          <div className="flex gap-2">
            <button
              className={`btn flex-1 ${duration === 86400 ? "btn-primary" : "btn-outline"}`}
              onClick={() => setDuration(86400)}
            >
              1 Day
            </button>
            <button
              className={`btn flex-1 ${duration === 604800 ? "btn-primary" : "btn-outline"}`}
              onClick={() => setDuration(604800)}
            >
              7 Days
            </button>
          </div>
        </div>

        {/* Max Players */}
        <div className="form-control">
          <label className="label">
            <span className="label-text">Max Players: {maxPlayers}</span>
          </label>
          <input
            type="range"
            min={2}
            max={10}
            value={maxPlayers}
            onChange={e => setMaxPlayers(Number(e.target.value))}
            className="range range-sm"
          />
          <div className="flex justify-between text-xs px-1 opacity-50">
            <span>2</span>
            <span>10</span>
          </div>
        </div>

        {/* Max Picks */}
        <div className="form-control">
          <label className="label">
            <span className="label-text">Max Picks per Player: {maxPicks}</span>
          </label>
          <div className="flex gap-2">
            {[1, 2, 3].map(n => (
              <button
                key={n}
                className={`btn flex-1 ${maxPicks === n ? "btn-primary" : "btn-outline"}`}
                onClick={() => {
                  setMaxPicks(n);
                  setPicks(prev => prev.slice(0, n));
                }}
              >
                {n}
              </button>
            ))}
          </div>
        </div>

        {/* House Cut */}
        <div className="form-control">
          <label className="label">
            <span className="label-text">House Cut: {houseCut}%</span>
          </label>
          <input
            type="range"
            min={0}
            max={10}
            value={houseCut}
            onChange={e => setHouseCut(Number(e.target.value))}
            className="range range-sm"
          />
          <div className="flex justify-between text-xs px-1 opacity-50">
            <span>0%</span>
            <span>10%</span>
          </div>
        </div>

        {/* Picks */}
        <div className="form-control">
          <label className="label">
            <span className="label-text">Your Picks (wallet addresses)</span>
          </label>
          {picks.map((pick, i) => (
            <input
              key={i}
              type="text"
              className="input input-bordered w-full mb-2 font-mono text-xs"
              placeholder="0x..."
              value={pick}
              onChange={e => {
                const newPicks = [...picks];
                newPicks[i] = e.target.value;
                setPicks(newPicks);
              }}
            />
          ))}
          {picks.length < maxPicks && (
            <button className="btn btn-sm btn-outline" onClick={() => setPicks([...picks, ""])}>
              + Add Pick
            </button>
          )}
        </div>

        {/* Estimates */}
        <div className="bg-base-200 rounded-lg p-4 space-y-1 text-sm">
          <div className="flex justify-between">
            <span className="opacity-50">Estimated Pot (if full):</span>
            <span className="font-mono">{formatEther(estimatedPot)} CLAWD</span>
          </div>
          <div className="flex justify-between">
            <span className="opacity-50">House Burn:</span>
            <span className="font-mono">{formatEther(estimatedBurn)} CLAWD</span>
          </div>
        </div>

        {/* Submit */}
        {spender && (
          <ThreeButtonFlow
            spender={spender}
            amount={entryFeeWei}
            onExecute={handleCreate}
            executeLabel="Create League"
            executePending={isMining}
            disabled={!canCreate}
          />
        )}
      </div>
    </div>
  );
};

export default CreateLeague;
