
#include "PresetsWidget.h"

QTestWidget::QTestWidget(QWidget* pParent, const QString& InternalName, const QString& UserInterfaceName) :
	QGroupBox(pParent),
	m_InternalName(InternalName),
	m_UserInterfaceName(UserInterfaceName)
{
	// Title, status and tooltip
	setTitle("Presets");
	setToolTip(UserInterfaceName + " presets");
	setStatusTip(UserInterfaceName + " presets");

	// Assign layout
	setLayout(&m_MainLayout);

	// Name edit
	m_PresetName.setEditable(false);
	m_PresetName.setFixedHeight(22);
	m_MainLayout.addWidget(&m_PresetName, 0, 0);

	// Load preset
	m_LoadPreset.setIcon(QIcon(":/Images/star--arrow.png"));
	m_LoadPreset.setToolTip("Load " + m_UserInterfaceName.toLower() + " preset");
	m_LoadPreset.setStatusTip("Load " + m_UserInterfaceName.toLower() + " preset");
	m_LoadPreset.setFixedWidth(22);
	m_LoadPreset.setFixedHeight(22);
	m_MainLayout.addWidget(&m_LoadPreset, 0, 1);

	// Save Preset
	m_SavePreset.setIcon(QIcon(":/Images/star--plus.png"));
	m_SavePreset.setToolTip("Save " + m_UserInterfaceName.toLower() + " Preset");
	m_SavePreset.setStatusTip("Save " + m_UserInterfaceName.toLower() + " preset");
	m_SavePreset.setFixedWidth(22);
	m_SavePreset.setFixedHeight(22);
	m_MainLayout.addWidget(&m_SavePreset, 0, 2);

	// Rename Preset
	m_RenamePreset.setIcon(QIcon(":/Images/star--pencil.png"));
	m_RenamePreset.setToolTip("Rename " + m_UserInterfaceName.toLower() + " Preset");
	m_RenamePreset.setStatusTip("Rename " + m_UserInterfaceName.toLower() + " preset");
	m_RenamePreset.setFixedWidth(22);
	m_RenamePreset.setFixedHeight(22);
	m_MainLayout.addWidget(&m_RenamePreset, 0, 3);

	// Remove preset
	m_RemovePreset.setIcon(QIcon(":/Images/star--minus.png"));
	m_RemovePreset.setToolTip("Remove " + m_UserInterfaceName.toLower() + " Preset");
	m_RemovePreset.setStatusTip("Remove " + m_UserInterfaceName.toLower() + " preset");
	m_RemovePreset.setFixedWidth(22);
	m_RemovePreset.setFixedHeight(22);
	m_MainLayout.addWidget(&m_RemovePreset, 0, 4);

	// Load presets
	m_LoadPresets.setIcon(QIcon(":/Images/table-import.png"));
	m_LoadPresets.setToolTip("Load " + m_UserInterfaceName.toLower() + " presets from file");
	m_LoadPresets.setStatusTip("Load " + m_UserInterfaceName.toLower() + " presets from file");
	m_LoadPresets.setFixedWidth(22);
	m_LoadPresets.setFixedHeight(22);
	m_MainLayout.addWidget(&m_LoadPresets, 0, 5);

	// Save presets
	m_SavePresets.setIcon(QIcon(":/Images/table-export.png"));
	m_SavePresets.setToolTip("Save " + m_UserInterfaceName.toLower() + " presets to file");
	m_SavePresets.setStatusTip("Save " + m_UserInterfaceName.toLower() + " presets to file");
	m_SavePresets.setFixedWidth(22);
	m_SavePresets.setFixedHeight(22);
	m_MainLayout.addWidget(&m_SavePresets, 0, 6);

	// Connections
	connect(&m_LoadPreset, SIGNAL(clicked()), this, SLOT(OnLoadPreset()));
	connect(&m_SavePreset, SIGNAL(clicked()), this, SLOT(OnSavePreset()));
	connect(&m_RenamePreset, SIGNAL(clicked()), this, SLOT(OnRenamePreset()));
	connect(&m_RemovePreset, SIGNAL(clicked()), this, SLOT(OnRemovePreset()));
	connect(&m_LoadPresets, SIGNAL(clicked()), this, SLOT(OnLoadPresets()));
	connect(&m_SavePresets, SIGNAL(clicked()), this, SLOT(OnSavePresets()));
	connect(&m_PresetName, SIGNAL(currentIndexChanged(int)), this, SLOT(OnCurrentIndexChanged(int)));
}

void QTestWidget::OnLoadPreset(void)
{
	if (m_PresetName.currentText().isEmpty())
		return;

	emit LoadPreset(m_PresetName.currentText());
}

void QTestWidget::OnSavePreset(void)
{
	QInputDialog InputDialog;

	InputDialog.setTextValue("");
	InputDialog.setLabelText("Name");
	InputDialog.setWindowIcon(QIcon(":/Images/pencil-field.png"));

	InputDialog.exec();

	emit SavePreset(InputDialog.textValue());
}

void QTestWidget::OnRenamePreset(void)
{
	if (m_PresetName.currentText().isEmpty())
		return;

	QInputDialog InputDialog;

	InputDialog.setTextValue(m_PresetName.currentText());
	InputDialog.setLabelText("Name");
	InputDialog.setWindowIcon(QIcon(":/Images/pencil-field.png"));

	InputDialog.exec();

	// Get new name
	QString Name = InputDialog.textValue();

	// Rename
	if (!Name.isEmpty())
		this->RenamePreset(m_PresetName.currentIndex(), Name);
}

void QTestWidget::OnRemovePreset(void)
{
	this->RemovePreset();
}

void QTestWidget::OnSavePresets(void)
{
	this->SavePresets(true);
}

void QTestWidget::OnLoadPresets(void)
{
	this->LoadPresets(true);
}

void QTestWidget::OnCurrentIndexChanged(int Index)
{
	if (Index <= 0)
		return;

	if (m_PresetName.lineEdit()->text().length() > 0)
	{
		m_LoadPreset.setEnabled(true);
		m_SavePreset.setEnabled(true);
	}
}