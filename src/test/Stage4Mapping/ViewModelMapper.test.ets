import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { EntityData } from '../../main/ets/mapping/EntityData';
import { ViewModelMapper, ViewModelMappingConfig } from '../../main/ets/mapping/ViewModelMapper';
import { EntityMappingError } from '../../main/ets/errors/MappingError';
import { MetadataStorage } from '../../main/ets/core/MetadataStorage';
import { ColumnMetadata } from '../../main/ets/core/ColumnMetadata';
import { ColumnType } from '../../main/ets/types/ColumnType';
import { ValueType } from '../../main/ets/types/ValueTypes';

class UserViewModel {
  id: number = 0;
  name: string = '';
  active: boolean = false;
}

const createEntityData = (): EntityData => {
  const data = new EntityData('User');
  data.addProperty('id', 1, 'number');
  data.addProperty('name', 'Alice', 'string');
  data.addProperty('active', true, 'boolean');
  return data;
};

const createMetadata = (): void => {
  const storage = MetadataStorage.getInstance();
  storage.registerEntity('User');
  storage.registerColumn('User', new ColumnMetadata('id', 'id').setType(ColumnType.INTEGER));
  storage.registerColumn('User', new ColumnMetadata('name', 'name').setType(ColumnType.TEXT));
  storage.registerColumn('User', new ColumnMetadata('active', 'active').setType(ColumnType.INTEGER));
};

const getViewModelValue = (viewModel: UserViewModel, propertyName: string): ValueType => {
  if (propertyName === 'id') {
    return viewModel.id;
  }
  if (propertyName === 'name') {
    return viewModel.name;
  }
  if (propertyName === 'active') {
    return viewModel.active;
  }
  return null;
};

export default function viewModelMapperTest() {
  describe('viewModelMapperTest', () => {
    beforeEach(() => {
      MetadataStorage.resetInstance();
      createMetadata();
    });

    it('toViewModel/toViewModelWithConfig should map values', 0, () => {
      const data = createEntityData();

      const view = ViewModelMapper.toViewModel(
        data,
        () => new UserViewModel(),
        (entity, model) => {
          model.id = entity.getPropertyValue('id') as number;
          model.name = String(entity.getPropertyValue('name'));
          model.active = Boolean(entity.getPropertyValue('active'));
        }
      );

      expect(view.id).assertEqual(1);
      expect(view.name).assertEqual('Alice');
      expect(view.active).assertEqual(true);

      const config = new ViewModelMappingConfig<UserViewModel>('User', () => new UserViewModel());
      config
        .addMapper((entity, model) => {
          model.name = String(entity.getPropertyValue('name'));
        })
        .addMapper((entity, model) => {
          model.id = Number(entity.getPropertyValue('id'));
        })
        .addMapper((entity, model) => {
          model.active = Boolean(entity.getPropertyValue('active'));
        });

      const configured = ViewModelMapper.toViewModelWithConfig(data, config);
      expect(configured.id).assertEqual(1);
      expect(configured.name).assertEqual('Alice');
      expect(configured.active).assertEqual(true);
    });

    it('toEntityData/toEntityDataWithConfig should map values', 0, () => {
      const viewModel = new UserViewModel();
      viewModel.id = 5;
      viewModel.name = 'Bob';
      viewModel.active = false;

      const entity = ViewModelMapper.toEntityData(
        viewModel,
        'User',
        ['id', 'name', 'active'],
        (model, propertyName) => getViewModelValue(model as UserViewModel, propertyName)
      );

      expect(entity.getPropertyValue('id')).assertEqual(5);
      expect(entity.getPropertyValue('name')).assertEqual('Bob');
      expect(entity.getPropertyValue('active')).assertEqual(false);

      const idProp = entity.getProperty('id');
      const nameProp = entity.getProperty('name');
      const activeProp = entity.getProperty('active');
      expect(idProp !== null).assertEqual(true);
      expect(nameProp !== null).assertEqual(true);
      expect(activeProp !== null).assertEqual(true);
      if (idProp && nameProp && activeProp) {
        expect(idProp.propertyType).assertEqual('number');
        expect(nameProp.propertyType).assertEqual('string');
        expect(activeProp.propertyType).assertEqual('boolean');
      }

      const config = new ViewModelMappingConfig<UserViewModel>('User', () => new UserViewModel());
      config.setReverseMapper(getViewModelValue, ['id', 'name', 'active']);
      const configuredEntity = ViewModelMapper.toEntityDataWithConfig(viewModel, config);
      expect(configuredEntity.getPropertyValue('id')).assertEqual(5);
      expect(configuredEntity.getPropertyValue('name')).assertEqual('Bob');
      expect(configuredEntity.getPropertyValue('active')).assertEqual(false);
    });

    it('toEntityDataWithConfig should throw when reverse mapper missing', 0, () => {
      const viewModel = new UserViewModel();
      const config = new ViewModelMappingConfig<UserViewModel>('User', () => new UserViewModel());
      let threw = false;
      try {
        ViewModelMapper.toEntityDataWithConfig(viewModel, config);
      } catch (error) {
        threw = error instanceof EntityMappingError;
      }
      expect(threw).assertEqual(true);
    });

    it('toPropertyMap/fromPropertyMap should map values', 0, () => {
      const entity = createEntityData();
      const map = ViewModelMapper.toPropertyMap(entity);
      expect(map.get('id')).assertEqual(1);
      expect(map.get('name')).assertEqual('Alice');
      expect(map.get('active')).assertEqual(true);

      const converted = ViewModelMapper.fromPropertyMap('User', map);
      expect(converted.getPropertyValue('id')).assertEqual(1);
      expect(converted.getPropertyValue('name')).assertEqual('Alice');
      expect(converted.getPropertyValue('active')).assertEqual(true);
    });
  });
}
