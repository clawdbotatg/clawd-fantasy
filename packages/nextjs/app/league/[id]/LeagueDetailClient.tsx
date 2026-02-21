"use client";

import { useState } from "react";
import { formatEther } from "viem";
import { useAccount } from "wagmi";
import { CountdownTimer } from "~~/components/clawd-fantasy/CountdownTimer";
import { PlayerList } from "~~/components/clawd-fantasy/PlayerList";
import { ThreeButtonFlow } from "~~/components/clawd-fantasy/ThreeButtonFlow";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";
import { useDeployedContractInfo } from "~~/hooks/scaffold-eth";

const STATUS_LABELS = ["Created", "Active", "Settled", "Cancelled"];

const LeagueDetailClient = ({ id }: { id: string }) => {
  const leagueId = BigInt(id);
  const { address } = useAccount();

  const { data: league, isLoading } = useScaffoldReadContract({
    contractName: "FantasyLeague",
    functionName: "leagues",
    args: [leagueId],
  });

  const { data: entries } = useScaffoldReadContract({
    contractName: "FantasyLeague",
    functionName: "getEntries",
    args: [leagueId],
  });

  const { data: winners } = useScaffoldReadContract({
    contractName: "FantasyLeague",
    functionName: "getWinners",
    args: [leagueId],
  });

  const { data: fantasyLeagueInfo } = useDeployedContractInfo({ contractName: "FantasyLeague" });
  const spender = fantasyLeagueInfo?.address || "";

  const { writeContractAsync: joinAsync, isMining: joinPending } = useScaffoldWriteContract({
    contractName: "FantasyLeague",
  });
  const { writeContractAsync: startAsync, isMining: startPending } = useScaffoldWriteContract({
    contractName: "FantasyLeague",
  });
  const { writeContractAsync: settleAsync, isMining: settlePending } = useScaffoldWriteContract({
    contractName: "FantasyLeague",
  });
  const { writeContractAsync: claimAsync, isMining: claimPending } = useScaffoldWriteContract({
    contractName: "FantasyLeague",
  });
  const { writeContractAsync: refundAsync, isMining: refundPending } = useScaffoldWriteContract({
    contractName: "FantasyLeague",
  });

  const [joinPicks, setJoinPicks] = useState<string[]>([""]);

  if (isLoading || !league) {
    return (
      <div className="flex justify-center py-20">
        <span className="loading loading-spinner loading-lg text-[#FF4136]" />
      </div>
    );
  }

  const [creator, entryFee, duration, maxPlayers, maxPicks, , endTime, totalPot, , status] =
    league as unknown as [string, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, number];
  const statusNum = Number(status);
  const playerCount = entries?.length ?? 0;
  const isFull = playerCount >= Number(maxPlayers);
  const isCreator = address?.toLowerCase() === creator.toLowerCase();
  const isPlayer = entries?.some((e: any) => e.player.toLowerCase() === address?.toLowerCase());
  const isWinner = winners?.some((w: string) => w.toLowerCase() === address?.toLowerCase());

  const nowSec = Math.floor(Date.now() / 1000);
  const leagueEnded = statusNum === 1 && endTime > 0n && nowSec >= Number(endTime);

  const validJoinPicks = joinPicks.filter(p => p.length === 42 && p.startsWith("0x"));

  const handleJoin = async () => {
    await joinAsync({
      functionName: "joinLeague",
      args: [leagueId, validJoinPicks as `0x${string}`[]],
    });
  };

  return (
    <div className="flex flex-col items-center px-4 py-8 max-w-2xl mx-auto w-full">
      <div className="w-full mb-6">
        <div className="flex justify-between items-center mb-2">
          <h1 className="text-2xl font-bold">League #{id}</h1>
          <span
            className={`badge ${statusNum === 2 ? "badge-warning" : statusNum === 1 ? "badge-success" : statusNum === 3 ? "badge-ghost" : "badge-info"}`}
          >
            {STATUS_LABELS[statusNum]}
          </span>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 bg-base-200 rounded-lg p-4 text-sm">
          <div>
            <div className="opacity-50 text-xs">Entry Fee</div>
            <div className="font-mono">{formatEther(entryFee)} CLAWD</div>
          </div>
          <div>
            <div className="opacity-50 text-xs">Pot</div>
            <div className="font-mono text-[#FFD700]">{formatEther(totalPot)} CLAWD</div>
          </div>
          <div>
            <div className="opacity-50 text-xs">Players</div>
            <div>
              {playerCount}/{Number(maxPlayers)}
            </div>
          </div>
          <div>
            <div className="opacity-50 text-xs">Duration</div>
            <div>{Number(duration) / 86400}d</div>
          </div>
        </div>

        {statusNum === 1 && endTime > 0n && !leagueEnded && (
          <div className="mt-3 text-center">
            <span className="opacity-50 text-sm mr-2">Ends in:</span>
            <CountdownTimer endTime={endTime} />
          </div>
        )}

        {leagueEnded && (
          <div className="mt-3 text-center text-[#FF4136] font-bold">
            ⏰ League ended — ready to settle!
          </div>
        )}
      </div>

      <div className="w-full space-y-4 mb-6">
        {/* Creator can start early if 2+ players */}
        {statusNum === 0 && isCreator && playerCount >= 2 && (
          <button
            className="btn bg-green-600 text-white hover:bg-green-700 w-full"
            disabled={startPending}
            onClick={() => startAsync({ functionName: "startLeague", args: [leagueId] })}
          >
            {startPending ? <span className="loading loading-spinner loading-sm" /> : "Start League"}
          </button>
        )}

        {/* Join form */}
        {statusNum === 0 && !isFull && !isPlayer && spender && (
          <div className="bg-base-200 rounded-lg p-4 space-y-3">
            <h3 className="font-bold">Join League</h3>
            <p className="text-xs opacity-50">Pick wallet address(es) you think will gain the most ETH</p>
            {joinPicks.map((pick, i) => (
              <input
                key={i}
                type="text"
                className="input input-bordered w-full font-mono text-xs"
                placeholder={`Pick ${i + 1} (0x...)`}
                value={pick}
                onChange={e => {
                  const np = [...joinPicks];
                  np[i] = e.target.value;
                  setJoinPicks(np);
                }}
              />
            ))}
            {joinPicks.length < Number(maxPicks) && (
              <button className="btn btn-sm btn-outline" onClick={() => setJoinPicks([...joinPicks, ""])}>
                + Add Pick
              </button>
            )}
            <ThreeButtonFlow
              spender={spender}
              amount={entryFee}
              onExecute={handleJoin}
              executeLabel="Join League"
              executePending={joinPending}
              disabled={validJoinPicks.length === 0}
            />
          </div>
        )}

        {/* Settle button — anyone can call after league ends */}
        {leagueEnded && (
          <button
            className="btn bg-[#FF4136] text-white hover:bg-[#FF4136]/80 w-full"
            disabled={settlePending}
            onClick={() => settleAsync({ functionName: "settleLeague", args: [leagueId] })}
          >
            {settlePending ? <span className="loading loading-spinner loading-sm" /> : "⚡ Settle League"}
          </button>
        )}

        {/* Claim winnings */}
        {statusNum === 2 && isWinner && (
          <button
            className="btn bg-[#FFD700] text-black hover:bg-[#FFD700]/80 w-full"
            disabled={claimPending}
            onClick={() => claimAsync({ functionName: "claimWinnings", args: [leagueId] })}
          >
            {claimPending ? <span className="loading loading-spinner loading-sm" /> : "🏆 Claim Winnings"}
          </button>
        )}

        {/* Refund on cancelled leagues */}
        {statusNum === 3 && isPlayer && (
          <button
            className="btn btn-outline w-full"
            disabled={refundPending}
            onClick={() => refundAsync({ functionName: "claimRefund", args: [leagueId] })}
          >
            {refundPending ? <span className="loading loading-spinner loading-sm" /> : "Claim Refund"}
          </button>
        )}
      </div>

      <div className="w-full">
        <h2 className="text-lg font-bold mb-3">Players ({playerCount})</h2>
        <PlayerList
          entries={(entries || []).map((e: any) => ({ player: e.player, picks: [...e.picks], claimed: e.claimed }))}
          winners={winners as string[] | undefined}
        />
      </div>
    </div>
  );
};

export default LeagueDetailClient;
