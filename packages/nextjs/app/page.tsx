"use client";

import { useState } from "react";
import Link from "next/link";
import { LeagueCard } from "~~/components/clawd-fantasy/LeagueCard";
import { useScaffoldReadContract } from "~~/hooks/scaffold-eth";

const STATUS_TABS = ["All", "Created", "Active", "Settled", "Cancelled"];

const Home = () => {
  const [activeTab, setActiveTab] = useState(0);

  const { data: leagueCount, isLoading } = useScaffoldReadContract({
    contractName: "FantasyLeague",
    functionName: "leagueCount",
  });

  const count = leagueCount ? Number(leagueCount) : 0;
  const leagueIds = Array.from({ length: count }, (_, i) => i);

  return (
    <div className="flex flex-col items-center px-4 py-8 max-w-4xl mx-auto w-full">
      <div className="flex justify-between items-center w-full mb-6">
        <h1 className="text-3xl font-bold">🦞 CLAWD Fantasy</h1>
        <Link href="/create" className="btn bg-[#FF4136] text-white hover:bg-[#FF4136]/80">
          + Create League
        </Link>
      </div>

      <div className="tabs tabs-boxed mb-6 w-full justify-center">
        {STATUS_TABS.map((tab, i) => (
          <a key={tab} className={`tab ${activeTab === i ? "tab-active" : ""}`} onClick={() => setActiveTab(i)}>
            {tab}
          </a>
        ))}
      </div>

      {isLoading ? (
        <div className="flex justify-center py-12">
          <span className="loading loading-spinner loading-lg text-[#FF4136]" />
        </div>
      ) : count === 0 ? (
        <div className="text-center py-12 opacity-50">
          <p className="text-xl mb-2">No leagues yet</p>
          <p>Create the first one!</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 w-full">
          {leagueIds.map(id => (
            <FilteredLeagueCard key={id} leagueId={id} filterStatus={activeTab === 0 ? null : activeTab - 1} />
          ))}
        </div>
      )}
    </div>
  );
};

const FilteredLeagueCard = ({ leagueId, filterStatus }: { leagueId: number; filterStatus: number | null }) => {
  const { data: league } = useScaffoldReadContract({
    contractName: "FantasyLeague",
    functionName: "leagues",
    args: [BigInt(leagueId)],
  });

  if (!league) return null;

  const statusIndex = 9; // status is the 10th field
  const leagueArray = league as unknown as unknown[];
  const status = Number(leagueArray[statusIndex]);

  if (filterStatus !== null && status !== filterStatus) return null;

  return <LeagueCard leagueId={leagueId} />;
};

export default Home;
