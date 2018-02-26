/* $Id: LongQueueC.nc,v 1.7 2009-06-25 18:37:24 scipio Exp $ */
/*
 * Copyright (c) 2006 Stanford University.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of the Stanford University nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL STANFORD
 * UNIVERSITY OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
 *  A general FIFO queue component, whose queue has a bounded size.
 *
 *  @author Philip Levis
 *  @author Geoffrey Mainland
 *  @date   $Date: 2009-06-25 18:37:24 $
 */

   
generic module LongQueueC(typedef queue_t, int QUEUE_SIZE) {
  provides interface LongQueue<queue_t>;
}

implementation {

  queue_t ONE_NOK queue[QUEUE_SIZE];
  int head = 0;
  int tail = 0;
  int size = 0;
  
  command bool LongQueue.empty() {
    return size == 0;
  }

  command bool LongQueue.full() {
     return size >= QUEUE_SIZE;
  }

  command int LongQueue.size() {
    return size;
  }

  command int LongQueue.maxSize() {
    return QUEUE_SIZE;
  }

  command queue_t LongQueue.head() {
    return queue[head];
  }

  void printLongQueue() {
#ifdef TOSSIM
    int i, j;
    dbg("LongQueueC", "head <-");
    for (i = head; i < head + size; i++) {
      dbg_clear("LongQueueC", "[");
      for (j = 0; j < sizeof(queue_t); j++) {
	int v = ((int*)&queue[i % QUEUE_SIZE])[j];
	dbg_clear("LongQueueC", "%0.2hhx", v);
      }
      dbg_clear("LongQueueC", "] ");
    }
    dbg_clear("LongQueueC", "<- tail\n");
#endif
  }
  
  command queue_t LongQueue.dequeue() {
    queue_t t = call LongQueue.head();
    dbg("LongQueueC", "%s: size is %hhu\n", __FUNCTION__, size);
    if (!call LongQueue.empty()) {
      head++;
      if (head == QUEUE_SIZE) head = 0;
      size--;
      printLongQueue();
    }
    return t;
  }

  command error_t LongQueue.enqueue(queue_t newVal) {
    if (call LongQueue.size() < call LongQueue.maxSize()) {
      dbg("LongQueueC", "%s: size is %hhu\n", __FUNCTION__, size);
      queue[tail] = newVal;
      tail++;
      if (tail == QUEUE_SIZE) tail = 0;
      size++;
      printLongQueue();
      return SUCCESS;
    }
    else {
      return FAIL;
    }
  }
  
  command queue_t LongQueue.element(int idx) {
    idx += head;
    if (idx >= QUEUE_SIZE) {
      idx -= QUEUE_SIZE;
    }
    return queue[idx];
  }  

}
