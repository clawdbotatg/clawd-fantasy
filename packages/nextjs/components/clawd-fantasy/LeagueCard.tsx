"use client";

import Link from "next/link";
import { CountdownTimer } from "./CountdownTimer";
import { formatEther } from "viem";
import { useScaffoldReadContract } from "~~/hooks/scaffold-eth";

const STATUS_LABELS = ["Created", "Active", "Settled", "Cancelled"];
const STATUS_COLORS = ["text-blue-400", "text-green-400", "text-[#FFD700]", "text-gray-400"];

export const LeagueCard = ({ leagueId }: { leagueId: number }) => {
  const { data: league, isLoading } = useScaffoldReadContract({
    contractName: "FantasyLeague",
    functionName: "leagues",
    args: [BigInt(leagueId)],
  });

  const { data: entries } = useScaffoldReadContract({
    contractName: "FantasyLeague",
    functionName: "getEntries",
    args: [BigInt(leagueId)],
  });

  if (isLoading || !league) {
    return <div className="card bg-base-200 border border-base-300 animate-pulse h-40" />;
  }

  const [, entryFee, duration, maxPlayers, , , endTime, totalPot, , status] = league as unknown as [
    string,
    bigint,
    bigint,
    bigint,
    bigint,
    bigint,
    bigint,
    bigint,
    bigint,
    number,
  ];
  const playerCount = entries?.length ?? 0;
  const statusNum = Number(status);

  return (
    <Link href={`/league/${leagueId}`}>
      <div className="card bg-base-200 border border-base-300 hover:border-[#FF4136]/50 transition-colors cursor-pointer p-4 space-y-2">
        <div className="flex justify-between items-center">
          <span className="font-bold text-lg">League #{leagueId}</span>
          <span className={`badge badge-sm ${STATUS_COLORS[statusNum]}`}>{STATUS_LABELS[statusNum]}</span>
        </div>

        <div className="grid grid-cols-2 gap-1 text-sm">
          <div>
            <span className="opacity-50">Entry:</span> <span className="font-mono">{formatEther(entryFee)} CLAWD</span>
          </div>
          <div>
            <span className="opacity-50">Players:</span>{" "}
            <span>
              {playerCount}/{Number(maxPlayers)}
            </span>
          </div>
          <div>
            <span className="opacity-50">Duration:</span> <span>{Number(duration) / 86400}d</span>
          </div>
          <div>
            <span className="opacity-50">Pot:</span> <span className="font-mono">{formatEther(totalPot)} CLAWD</span>
          </div>
        </div>

        {statusNum === 1 && endTime > 0n && (
          <div className="text-sm">
            <span className="opacity-50">Ends in:</span> <CountdownTimer endTime={endTime} />
          </div>
        )}
      </div>
    </Link>
  );
};
