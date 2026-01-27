import { describe, it, expect } from '@ohos/hypium';
import { EntityDataInput } from '../../main/ets/mapping/EntityDataInput';

export default function entityDataInputTest() {
  describe('entityDataInputTest', () => {
    it('set/get/has/keys/remove/size/clear should work', 0, () => {
      const input = EntityDataInput.create();
      input.set('name', 'Alice');
      input.set('age', 18);
      input.set('active', true);

      expect(input.get('name')).assertEqual('Alice');
      expect(input.get('missing') === null).assertEqual(true);
      expect(input.has('age')).assertEqual(true);
      expect(input.has('missing')).assertEqual(false);

      const keys = input.keys();
      expect(keys.length).assertEqual(3);
      expect(keys.includes('name')).assertEqual(true);
      expect(keys.includes('age')).assertEqual(true);
      expect(keys.includes('active')).assertEqual(true);

      expect(input.size()).assertEqual(3);

      input.remove('age');
      expect(input.has('age')).assertEqual(false);
      expect(input.get('age') === null).assertEqual(true);
      expect(input.size()).assertEqual(2);

      input.clear();
      expect(input.size()).assertEqual(0);
      expect(input.keys().length).assertEqual(0);
      expect(input.get('name') === null).assertEqual(true);
    });
  });
}
