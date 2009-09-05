/**
	Taken from Defend's engine.util.MT
*/

module xf.build.MT;


version (MultiThreaded) {
	private {
		import tango.core.sync.Counter;
		import tango.stdc.stdlib : alloca, abort;
		import tango.core.Thread;
		import tango.util.log.Trace;
	}

	public {
		import tango.core.ThreadPool;
	}

	alias ThreadPool!(void*) ThreadPoolT;




	struct MTFor
	{
		ThreadPoolT threadPool;
		int from, to;
		int numPerTask;
		
		static MTFor opCall(ThreadPoolT threadPool, int from, int to, int numPerTask = 0)
		{
			assert(to >= from);
		
			MTFor result;
			result.threadPool = threadPool;
			result.from = from;
			result.to = to;
			
			if(numPerTask == 0)
			{
				result.numPerTask = (to - from) / 4;
				
				if(result.numPerTask == 0) // (to - from) < 4
					result.numPerTask = 1;
			}
			else
				result.numPerTask = numPerTask;

			return result;
		}
		
		int opApply(int delegate(ref int) dg)
		{
			if(to == from)
				return 0;
		
			assert(numPerTask > 0);
		
			Flag!(int) numLeft;
			int numTasks = (to - from) / numPerTask;
			
			assert(numTasks > 0);
			numLeft = numTasks - 1;
			
			void run(int idx)
			{
				int i, start;
				i = start = idx * numPerTask;
				
				while(i < to && i - start < numPerTask)
				{
					dg(i);
					++i;
				}
			}
			
			void task(void* arg)
			{
				try {
					run(cast(int)arg);
				} catch (Exception e) {
					char[] error;
					e.writeOut((char[] msg) { error ~= msg; });
					Trace.formatln("{}", error);
					abort();
				}
				--numLeft;
			}
			
			for(int i = 0; i < numTasks - 1; ++i)
				threadPool.append(&task, cast(void*)i);
			
			run(numTasks - 1);
			
			while(numLeft() > 0)
				{}
				
			return 0;
		}
	}

	MTFor mtFor(ThreadPoolT threadPool, int from, int to, int numPerTask = 0)
	{
		return MTFor(threadPool, from, to, numPerTask);
	}
}